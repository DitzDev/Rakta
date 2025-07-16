import uri, httpcore, tables, strutils, asyncdispatch
import types

# let cookieRegex = re"([^=]+)=([^;]*)"

proc parseQueryParams(uri: Uri): Table[string, string] =
  result = initTable[string, string]()
  if uri.query.len > 0:
    for pair in uri.query.split('&'):
      let eqPos = pair.find('=')
      if eqPos != -1:
        let key = decodeUrl(pair[0..<eqPos])
        let value = decodeUrl(pair[eqPos+1..^1])
        result[key] = value

proc parseCookies(cookieHeader: string): Table[string, string] =
  result = initTable[string, string]()
  if cookieHeader.len == 0:
    return

  for cookie in cookieHeader.split(';'):
    let trimmed = cookie.strip()
    let eqPos = trimmed.find('=')
    if eqPos != -1:
      let key = trimmed[0..<eqPos].strip()
      let value = trimmed[eqPos+1..^1].strip()
      result[key] = value

proc newRequest*(httpMethod: HttpMethod, path: string, headers: HttpHeaders = newHttpHeaders(), body: string = ""): Request =
  let uri = parseUri(path)
  
  result = Request(
    httpMethod: httpMethod,
    path: uri.path,
    headers: headers,
    body: body,
    query: parseQueryParams(uri),
    cookies: initTable[string, string]()
  )
    
  if headers.hasKey("Cookie"):
    result.cookies = parseCookies(headers["Cookie"])

proc newResponse*(): Response =
  result = Response(
    status: Http200,
    headers: newHttpHeaders(),
    body: "",
    sent: false
  )

proc newContext*(req: Request, res: Response, app: App): Context = 
  result = Context(
    req: req,
    res: res,
    params: initTable[string, string](),
    nextCalled: false,
    middlewareIndex: 0,
    app: app
  )

proc next*(ctx: Context): Future[void] {.async.} =
  ## Proceeds to the next middleware or route handler in the chain.
  ## 
  ## This function signals that the current middleware has completed its
  ## processing and the next middleware or route handler should be executed.
  ## Must be called within middleware to continue the request processing.
  ## 
  ## Example:
  ##   ```nim
  ##   app.use(proc(ctx: Context): Future[void] {.async.} =
  ##     echo "Processing request"
  ##     await ctx.next()  # Continue to next middleware/handler
  ##   )
  ##   ```
  ctx.nextCalled = true