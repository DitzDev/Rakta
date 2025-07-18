import asyncdispatch, httpcore, json, strutils, tables, os, times
import types

proc newSendFileOptions*(): SendFileOptions =
  result = SendFileOptions(
    headers: initTable[string, string](),
    root: "",
    maxAge: 0,
    lastModified: true,
    etag: false,
    dotfiles: "ignore"
  )

const mimeTypes = {
  ".html": "text/html",
  ".htm": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".mjs": "application/javascript",
  ".json": "application/json",
  ".xml": "application/xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".bmp": "image/bmp",
  ".tiff": "image/tiff",
  ".txt": "text/plain",
  ".pdf": "application/pdf",
  ".doc": "application/msword",
  ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ".xls": "application/vnd.ms-excel",
  ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ".ppt": "application/vnd.ms-powerpoint",
  ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ".zip": "application/zip",
  ".rar": "application/x-rar-compressed",
  ".7z": "application/x-7z-compressed",
  ".tar": "application/x-tar",
  ".gz": "application/gzip",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
  ".ogg": "audio/ogg",
  ".mp4": "video/mp4",
  ".avi": "video/x-msvideo",
  ".mov": "video/quicktime",
  ".wmv": "video/x-ms-wmv",
  ".flv": "video/x-flv",
  ".webm": "video/webm",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".eot": "application/vnd.ms-fontobject"
}.toTable()

proc getMimeTypeFromExt(ext: string): string =
  let lowerExt = ext.toLowerAscii()
  if mimeTypes.hasKey(lowerExt):
    return mimeTypes[lowerExt]
  return "application/octet-stream"

proc isHiddenFile(filename: string): bool =
  let basename = extractFilename(filename)
  return basename.startsWith(".")

proc formatHttpDate(time: Time): string =
  let utcTime = time.utc
  return utcTime.format("ddd, dd MMM yyyy HH:mm:ss") & " GMT"

proc generateETag(filePath: string, fileInfo: FileInfo): string =
  let mtime = fileInfo.lastWriteTime.toUnix()
  let size = fileInfo.size
  return "\"" & $mtime & "-" & $size & "\""

proc status*(ctx: Context, code: HttpCode): Context =
  ## Sets the HTTP status code for the response.
  ## 
  ## This function sets the status code that will be sent to the client.
  ## Returns the context for method chaining.
  ## 
  ## Parameters:
  ##   code: HTTP status code (e.g., Http200, Http404, Http500)
  ## 
  ## Returns:
  ##   Context: The same context for method chaining
  ## 
  ## Example:
  ##   ```nim
  ##   discard ctx.status(Http404)
  ##   await ctx.send("Not Found")
  ##   
  ##   # Method chaining
  ##   await ctx.status(Http200).json(%*{"success": true})
  ##   ```
  ctx.res.status = code
  return ctx

proc endRes*(ctx: Context): Future[void] {.async.} =
  ## Ends the response process without sending any body content.
  ## This is useful for sending responses with status codes only,
  ## similar to Express.js res.end().
  ## 
  ## The response will be sent with the current status code and headers,
  ## but with an empty body.
  ## 
  ## Example:
  ##   ```nim
  ##   ctx.status(Http400)
  ##   await ctx.endRes()
  ##   ```
  if ctx.res.sent:
    return
  ctx.res.body = ""
  ctx.res.sent = true

proc setHeader*(ctx: Context, name: string, value: string): Context =
  ## Sets a response header with the specified name and value.
  ## 
  ## This function adds or updates a header in the HTTP response.
  ## Returns the context for method chaining.
  ## 
  ## Parameters:
  ##   name: Header name (e.g., "Content-Type", "Cache-Control")
  ##   value: Header value
  ## 
  ## Returns:
  ##   Context: The same context for method chaining
  ## 
  ## Example:
  ##   ```nim
  ##   discard ctx.setHeader("Content-Type", "application/json")
  ##   discard ctx.setHeader("Cache-Control", "no-cache")
  ##   ```
  ctx.res.headers[name] = value
  return ctx

proc getHeader*(ctx: Context, name: string): string =
  ## Retrieves a header value by name from the request.
  ## 
  ## This function looks up a header in the request headers and returns
  ## its value. Header names are case-insensitive. If the header is not
  ## found, returns an empty string.
  ## 
  ## Parameters:
  ##   name: Header name to retrieve (case-insensitive)
  ## 
  ## Returns:
  ##   string: Header value or empty string if not found
  ## 
  ## Example:
  ##   ```nim
  ##   let contentType = ctx.getHeader("Content-Type")
  ##   let userAgent = ctx.getHeader("User-Agent")
  ##   let auth = ctx.getHeader("Authorization")
  ##   
  ##   if auth != "":
  ##     echo "Authorization header found: ", auth
  ##   
  ##   # Case-insensitive lookup
  ##   let accept = ctx.getHeader("accept")  # Same as "Accept"
  ##   ```
  # HTTP headers are case-insensitive, so we need to do case-insensitive lookup
  let lowerName = name.toLowerAscii()
  
  # Check if headers exist in request
  if ctx.req.headers.hasKey(name):
    return ctx.req.headers[name]
  
  # Try case-insensitive lookup
  for key, value in ctx.req.headers.pairs:
    if key.toLowerAscii() == lowerName:
      return value
  
  return ""

proc setCookie*(ctx: Context, name: string, value: string, httpOnly: bool = false, secure: bool = false, sameSite: string = "Lax"): Context =
  ## Sets a cookie in the HTTP response.
  ## 
  ## This function adds a Set-Cookie header to the response with the specified
  ## cookie name, value, and security options.
  ## 
  ## Parameters:
  ##   name: Cookie name
  ##   value: Cookie value
  ##   httpOnly: If true, cookie is only accessible via HTTP (not JavaScript)
  ##   secure: If true, cookie is only sent over HTTPS
  ##   sameSite: SameSite attribute ("Strict", "Lax", or "None")
  ## 
  ## Returns:
  ##   Context: The same context for method chaining
  ## 
  ## Example:
  ##   ```nim
  ##   discard ctx.setCookie("session", "abc123", httpOnly = true, secure = true)
  ##   discard ctx.setCookie("theme", "dark", sameSite = "Strict")
  ##   ```
  var cookieValue = name & "=" & value
  if httpOnly:
    cookieValue.add("; HttpOnly")
  if secure:
    cookieValue.add("; Secure")
  cookieValue.add("; SameSite=" & sameSite)
  
  if ctx.res.headers.hasKey("Set-Cookie"):
    ctx.res.headers["Set-Cookie"] = ctx.res.headers["Set-Cookie"] & ", " & cookieValue
  else:
    ctx.res.headers["Set-Cookie"] = cookieValue
  return ctx

proc send*(ctx: Context, content: string): Future[void] {.async.} =
  ## Sends a plain text response to the client.
  ## 
  ## This function sends the specified content as the response body.
  ## The response is marked as sent to prevent further modifications.
  ## 
  ## Parameters:
  ##   content: Text content to send to the client
  ## 
  ## Example:
  ##   ```nim
  ##   await ctx.send("Hello World")
  ##   await ctx.send("Error: Resource not found")
  ##   ```
  if ctx.res.sent:
    return
  ctx.res.body = content
  ctx.res.sent = true

proc json*(ctx: Context, data: JsonNode): Future[void] {.async.} =
  ## Sends a JSON response to the client.
  ## 
  ## This function sets the Content-Type header to application/json and
  ## sends the JSON data as the response body.
  ## 
  ## Parameters:
  ##   data: JsonNode containing the data to send
  ## 
  ## Example:
  ##   ```nim
  ##   await ctx.json(%*{"message": "Hello", "status": "success"})
  ##   await ctx.json(%*{"users": [{"id": 1, "name": "John"}]})
  ##   ```
  if ctx.res.sent:
    return
  discard ctx.setHeader("Content-Type", "application/json")
  ctx.res.body = $data
  ctx.res.sent = true

proc jsonBody*(ctx: Context): JsonNode =
  ## Parses the request body as JSON.
  ## 
  ## This function attempts to parse the request body as JSON and returns
  ## the parsed JsonNode. If parsing fails, returns a null JsonNode.
  ## 
  ## Returns:
  ##   JsonNode: Parsed JSON data or null if parsing fails
  ## 
  ## Example:
  ##   ```nim
  ##   let userData = ctx.jsonBody()
  ##   if userData.hasKey("name"):
  ##     echo "User name: ", userData["name"].getStr()
  ##   ```
  try:
    return parseJson(ctx.req.body)
  except:
    return newJNull()

proc getCookie*(ctx: Context, name: string): string =
  ## Retrieves a cookie value by name from the request.
  ## 
  ## This function looks up a cookie in the request headers and returns
  ## its value. If the cookie is not found, returns an empty string.
  ## 
  ## Parameters:
  ##   name: Cookie name to retrieve
  ## 
  ## Returns:
  ##   string: Cookie value or empty string if not found
  ## 
  ## Example:
  ##   ```nim
  ##   let sessionId = ctx.getCookie("session")
  ##   if sessionId != "":
  ##     echo "Session ID: ", sessionId
  ##   ```
  if ctx.req.cookies.hasKey(name):
    return ctx.req.cookies[name]
  return ""

proc getQuery*(ctx: Context, name: string): string =
  ## Retrieves a query parameter value by name from the request URL.
  ## 
  ## This function extracts a query parameter from the request URL.
  ## If the parameter is not found, returns an empty string.
  ## 
  ## Parameters:
  ##   name: Query parameter name to retrieve
  ## 
  ## Returns:
  ##   string: Query parameter value or empty string if not found
  ## 
  ## Example:
  ##   ```nim
  ##   # For URL: /search?q=hello&lang=en
  ##   let searchQuery = ctx.getQuery("q")      # Returns "hello"
  ##   let language = ctx.getQuery("lang")      # Returns "en"
  ##   let missing = ctx.getQuery("missing")    # Returns ""
  ##   ```
  if ctx.req.query.hasKey(name):
    let value = ctx.req.query[name]
    return value
  return ""

proc getParam*(ctx: Context, name: string): string =
  ## Retrieves a route parameter value by name.
  ## 
  ## This function extracts a parameter from the route pattern.
  ## Route parameters are defined with colon syntax (e.g., "/users/:id").
  ## If the parameter is not found, returns an empty string.
  ## 
  ## Parameters:
  ##   name: Route parameter name to retrieve
  ## 
  ## Returns:
  ##   string: Route parameter value or empty string if not found
  ## 
  ## Example:
  ##   ```nim
  ##   # For route "/users/:id" and URL "/users/123"
  ##   let userId = ctx.getParam("id")  # Returns "123"
  ##   
  ##   # For route "/posts/:category/:slug"
  ##   let category = ctx.getParam("category")
  ##   let slug = ctx.getParam("slug")
  ##   ```
  if ctx.params.hasKey(name):
    return ctx.params[name]
  return ""

proc sendFile*(ctx: Context, filePath: string, options: SendFileOptions = newSendFileOptions()): Future[void] {.async.} =
  ## Sends a file to the client with advanced options.
  ## 
  ## This function sends a file as the response with proper MIME type detection,
  ## caching headers, and security options. Supports custom headers and file
  ## serving options.
  ## 
  ## Parameters:
  ##   filePath: Path to the file to send
  ##   options: SendFileOptions with headers, caching, and security settings
  ## 
  ## Example:
  ##   ```nim
  ##   # Basic file sending
  ##   await ctx.sendFile("index.html")
  ##   
  ##   # With custom options
  ##   var options = newSendFileOptions()
  ##   options.maxAge = 3600  # Cache for 1 hour
  ##   options.etag = true
  ##   await ctx.sendFile("static/app.js", options)
  ##   ```
  if ctx.res.sent:
    return
  
  var actualFilePath: string
  
  # Priority: options.root > app.staticRoot > filePath as-is
  if options.root != "":
    actualFilePath = options.root / filePath
  elif ctx.app.staticRoot != "":
    actualFilePath = ctx.app.staticRoot / filePath
  else:
    actualFilePath = filePath
  
  actualFilePath = expandFilename(actualFilePath)
  
  if not fileExists(actualFilePath):
    discard ctx.status(Http404)
    await ctx.send("File not found")
    return
  
  if options.dotfiles == "deny" and isHiddenFile(actualFilePath):
    discard ctx.status(Http403)
    await ctx.send("Forbidden")
    return
  elif options.dotfiles == "ignore" and isHiddenFile(actualFilePath):
    discard ctx.status(Http404)
    await ctx.send("File not found")
    return
  
  try:
    let fileInfo = getFileInfo(actualFilePath)
    let content = readFile(actualFilePath)
    let ext = splitFile(actualFilePath).ext
    let mimeType = getMimeTypeFromExt(ext)
    
    discard ctx.setHeader("Content-Type", mimeType)
    discard ctx.setHeader("Content-Length", $content.len)
    
    for key, value in options.headers.pairs:
      discard ctx.setHeader(key, value)
    
    if options.lastModified:
      discard ctx.setHeader("Last-Modified", formatHttpDate(fileInfo.lastWriteTime))
    
    if options.etag:
      let etag = generateETag(actualFilePath, fileInfo)
      discard ctx.setHeader("ETag", etag)
    
    if options.maxAge > 0:
      discard ctx.setHeader("Cache-Control", "public, max-age=" & $options.maxAge)
    
    discard ctx.setHeader("Accept-Ranges", "bytes")
    
    await ctx.send(content)
    
  except IOError as e:
    echo "Error reading file: ", e.msg
    discard ctx.status(Http500)
    await ctx.send("Internal Server Error")
  except Exception as e:
    echo "Unexpected error: ", e.msg
    discard ctx.status(Http500)
    await ctx.send("Internal Server Error")

proc sendFile*(ctx: Context, filePath: string, headers: Table[string, string]): Future[void] {.async.} =
  ## Sends a file to the client with custom headers.
  ## 
  ## This is a convenience overload that sends a file with custom headers.
  ## The file is sent with appropriate MIME type detection and the specified
  ## custom headers.
  ## 
  ## Parameters:
  ##   filePath: Path to the file to send
  ##   headers: Table of custom headers to include in the response
  ## 
  ## Example:
  ##   ```nim
  ##   let customHeaders = {
  ##     "Content-Disposition": "attachment; filename=document.pdf",
  ##     "X-Custom-Header": "MyValue"
  ##   }.toTable()
  ##   await ctx.sendFile("files/document.pdf", customHeaders)
  ##   ```
  var options = newSendFileOptions()
  options.headers = headers
  await ctx.sendFile(filePath, options)