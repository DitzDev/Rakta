import asyncdispatch, asynchttpserver, httpcore, strutils, uri, tables
import Rakta/types, Rakta/router, Rakta/response, Rakta/context, Rakta/cors, Rakta/static

export types, response, context, cors

proc addBrandingHeaders(ctx: Context): Future[void] {.async, gcsafe.} =
  discard ctx.setHeader("X-Powered-By", "Rakta")
  discard ctx.setHeader("X-Rakta-Version", "0.1.0")
  await ctx.next()

proc executeMiddlewares(ctx: Context): Future[void] {.async, gcsafe.} =
  if ctx.middlewareIndex < ctx.app.middlewares.len:
    let middleware = ctx.app.middlewares[ctx.middlewareIndex]
    ctx.middlewareIndex += 1
    ctx.nextCalled = false
    await middleware(ctx)
    if ctx.nextCalled:
      await executeMiddlewares(ctx)

proc newApp*(): App =
  ## Creates a new Rakta application instance.
  ## 
  ## This function initializes a new web application with default settings,
  ## including empty routes, middlewares, and default port 3000.
  ## Automatically adds branding headers middleware.
  ## 
  ## Returns:
  ##   App: A new application instance ready to be configured
  ## 
  ## Example:
  ##   ```nim
  ##   let app = newApp()
  ##   ```
  result = App(
    routes: @[],
    middlewares: @[],
    port: 3000,
    staticRoot: "",
    exactRoutes: initTable[string, Route](),
    routesByMethod: initTable[HttpMethod, seq[Route]]()
  )

  result.middlewares.add(addBrandingHeaders)

proc setStaticRoot*(app: App, rootDir: string) =
  app.staticRoot = rootDir

proc serveStatic*(app: App, staticDir: string, urlPrefix: string = ""): Handler =
  ## Creates a static file serving middleware for the application.
  ## 
  ## This middleware serves static files from the specified directory.
  ## Files are served with appropriate MIME types and caching headers.
  ## 
  ## Parameters:
  ##   staticDir: Directory path containing static files to serve
  ##   urlPrefix: Optional URL prefix for static routes (default: "")
  ## 
  ## Returns:
  ##   Handler: Middleware function that serves static files
  ## 
  ## Example:
  ##   ```nim
  ##   app.use(app.serveStatic("public"))
  ##   app.use(app.serveStatic("assets", "/static"))
  ##   ```
  if app.staticRoot == "":
    app.setStaticRoot(staticDir)
  
  return serveStatic(staticDir, urlPrefix)

proc get*(app: App, pattern: string, handler: Handler) =
  ## Registers a GET route handler for the specified pattern.
  ## 
  ## Supports both exact matches and parameterized routes using :param syntax.
  ## Route parameters can be accessed via ctx.getParam("paramName").
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/users/:id", "/api/status")
  ##   handler: Async function to handle the request
  ## 
  ## Example:
  ##   ```nim
  ##   app.get("/", proc(ctx: Context): Future[void] {.async.} =
  ##     await ctx.send("Hello World")
  ##   )
  ##   
  ##   app.get("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.getParam("id")
  ##     await ctx.json(%*{"userId": userId})
  ##   )
  ##   ```
  app.addRoute(HttpGet, pattern, handler)

proc post*(app: App, pattern: string, handler: Handler) =
  ## Registers a POST route handler for the specified pattern.
  ## 
  ## Supports both exact matches and parameterized routes using :param syntax.
  ## Route parameters can be accessed via ctx.getParam("paramName").
  ## Request body can be accessed via ctx.req.body or ctx.jsonBody().
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/api/users", "/submit/:type")
  ##   handler: Async function to handle the request
  ## 
  ## Example:
  ##   ```nim
  ##   app.post("/api/users", proc(ctx: Context): Future[void] {.async.} =
  ##     let userData = ctx.jsonBody()
  ##     await ctx.json(%*{"created": userData})
  ##   )
  ##   ```
  app.addRoute(HttpPost, pattern, handler)

proc put*(app: App, pattern: string, handler: Handler) =
  ## Registers a PUT route handler for the specified pattern.
  ## 
  ## Supports both exact matches and parameterized routes using :param syntax.
  ## Route parameters can be accessed via ctx.getParam("paramName").
  ## Request body can be accessed via ctx.req.body or ctx.jsonBody().
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/api/users/:id")
  ##   handler: Async function to handle the request
  ## 
  ## Example:
  ##   ```nim
  ##   app.put("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.getParam("id")
  ##     let userData = ctx.jsonBody()
  ##     await ctx.json(%*{"updated": userId, "data": userData})
  ##   )
  ##   ```
  app.addRoute(HttpPut, pattern, handler)

proc delete*(app: App, pattern: string, handler: Handler) =
  ## Registers a DELETE route handler for the specified pattern.
  ## 
  ## Supports both exact matches and parameterized routes using :param syntax.
  ## Route parameters can be accessed via ctx.getParam("paramName").
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/api/users/:id")
  ##   handler: Async function to handle the request
  ## 
  ## Example:
  ##   ```nim
  ##   app.delete("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.getParam("id")
  ##     await ctx.json(%*{"deleted": userId})
  ##   )
  ##   ```
  app.addRoute(HttpDelete, pattern, handler)

proc use*(app: App, middleware: Handler) =
  ## Adds a middleware function to the application.
  ## 
  ## Middleware functions are executed in order before route handlers.
  ## They can modify the request/response or call ctx.next() to continue
  ## to the next middleware or route handler.
  ## 
  ## Parameters:
  ##   middleware: Async middleware function that processes Context
  ## 
  ## Example:
  ##   ```nim
  ##   app.use(corsMiddleware())
  ##   app.use(app.serveStatic("public"))
  ##   
  ##   app.use(proc(ctx: Context): Future[void] {.async.} =
  ##     echo "Request to ", ctx.req.path
  ##     await ctx.next()
  ##   )
  ##   ```
  app.middlewares.add(middleware)

proc handleRequest(app: App, httpReq: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
  var fullUrl = httpReq.url.path
  if httpReq.url.query.len > 0:
    fullUrl = fullUrl & "?" & httpReq.url.query
  
  let req = newRequest(httpReq.reqMethod, fullUrl, httpReq.headers, httpReq.body)
  let res = newResponse()
  let ctx = newContext(req, res, app)
  
  try:
    await executeMiddlewares(ctx)
    
    if not ctx.res.sent:
      let (route, params) = app.findRoute(ctx.req.httpMethod, ctx.req.path)
      if route != nil:
        ctx.params = params
        await route.handler(ctx)
      else:
        discard ctx.status(Http404)
        await ctx.send("Not Found")

    await httpReq.respond(ctx.res.status, ctx.res.body, ctx.res.headers)
  except Exception as e:
    echo "Error handling request: ", e.msg
    await httpReq.respond(Http500, "Internal Server Error")

proc listen*(app: App, port: int, callback: proc() = nil) {.async.} =
  ## Starts the HTTP server on the specified port.
  ## 
  ## This function starts the web server and begins listening for incoming
  ## HTTP requests. The server will handle requests using the configured
  ## routes and middleware.
  ## 
  ## Parameters:
  ##   port: Port number to listen on (e.g., 3000, 8080)
  ##   callback: Optional callback function to execute when server starts
  ## 
  ## Example:
  ##   ```nim
  ##   waitFor app.listen(3000, proc() =
  ##     echo "Server running at http://localhost:3000"
  ##   )
  ##   ```
  app.port = port
  let server = newAsyncHttpServer()
  
  proc handleRequestWrapper(req: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
    await app.handleRequest(req)
  
  if callback != nil:
    callback()
  
  await server.serve(Port(port), handleRequestWrapper)