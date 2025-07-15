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
  ctx.res.status = code
  return ctx

proc setHeader*(ctx: Context, name: string, value: string): Context =
  ctx.res.headers[name] = value
  return ctx

proc setCookie*(ctx: Context, name: string, value: string, httpOnly: bool = false, secure: bool = false, sameSite: string = "Lax"): Context =
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
  if ctx.res.sent:
    return
  ctx.res.body = content
  ctx.res.sent = true

proc json*(ctx: Context, data: JsonNode): Future[void] {.async.} =
  if ctx.res.sent:
    return
  discard ctx.setHeader("Content-Type", "application/json")
  ctx.res.body = $data
  ctx.res.sent = true

proc jsonBody*(ctx: Context): JsonNode =
  try:
    return parseJson(ctx.req.body)
  except:
    return newJNull()

proc getCookie*(ctx: Context, name: string): string =
  if ctx.req.cookies.hasKey(name):
    return ctx.req.cookies[name]
  return ""

proc getQuery*(ctx: Context, name: string): string =
  if ctx.req.query.hasKey(name):
    let value = ctx.req.query[name]
    return value
  return ""

proc getParam*(ctx: Context, name: string): string =
  if ctx.params.hasKey(name):
    return ctx.params[name]
  return ""

proc sendFile*(ctx: Context, filePath: string, options: SendFileOptions = newSendFileOptions()): Future[void] {.async.} =
  if ctx.res.sent:
    return
  
  var actualFilePath: string
 
  if options.root != "":
    actualFilePath = options.root / filePath
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
  var options = newSendFileOptions()
  options.headers = headers
  await ctx.sendFile(filePath, options) 