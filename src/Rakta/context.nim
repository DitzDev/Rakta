import uri, httpcore, tables, strutils, asyncdispatch
import types

proc newRequest*(httpMethod: HttpMethod, url: string, headers: HttpHeaders, body: string): Request =
  let uri = parseUri(url)
  let path = uri.path
  
  var query = initTable[string, string]()
  if uri.query.len > 0:
    for pair in uri.query.split('&'):
      let parts = pair.split('=', 1)
      if parts.len == 2:
        query[parts[0]] = parts[1]
  
  var cookies = initTable[string, string]()
  if headers.hasKey("Cookie"):
    let cookieHeader = headers["Cookie"]
    for cookie in cookieHeader.split(';'):
      let parts = cookie.strip().split('=', 1)
      if parts.len == 2:
        cookies[parts[0]] = parts[1]
  
  return Request(
    httpMethod: httpMethod,
    path: path,
    headers: headers,
    body: body,
    query: query,
    cookies: cookies
  )

proc newResponse*(): Response =
  return Response(
    status: Http200,
    headers: newHttpHeaders(),
    body: "",
    sent: false
  )

proc newContext*(req: Request, res: Response, app: App): Context =
  return Context(
    req: req,
    res: res,
    params: initTable[string, string](),
    nextCalled: false,
    middlewareIndex: 0,
    pathMiddlewareIndex: 0,
    routeMiddlewares: @[],
    app: app
  )

proc next*(ctx: Context): Future[void] {.async.} =
  ## Calls the next middleware in the chain.
  ## 
  ## This function signals that the current middleware has finished
  ## and control should pass to the next middleware or route handler.
  ## 
  ## Example:
  ##   ```nim
  ##   app.use(proc(ctx: Context): Future[void] {.async.} =
  ##     echo "Before processing"
  ##     await ctx.next()  # Continue to next middleware
  ##     echo "After processing"
  ##   )
  ##   ```
  ctx.nextCalled = true