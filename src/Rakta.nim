import asyncdispatch, asynchttpserver, httpcore, strutils, uri, tables
import Rakta/types, Rakta/router, Rakta/response, Rakta/context, Rakta/cors, Rakta/static, Rakta/middleware

export types, response, context, cors

# Export all HTTP status codes from httpcore
# This allows users to access them directly without needing to import httpcore.
export
  Http100, Http101, Http102, Http103,
  Http200, Http201, Http202, Http203, Http204, Http205, Http206, Http207, Http208, Http226,
  Http300, Http301, Http302, Http303, Http304, Http305, Http307, Http308,
  Http400, Http401, Http402, Http403, Http404, Http405, Http406, Http407, Http408, Http409, Http410,
  Http411, Http412, Http413, Http414, Http415, Http416, Http417, Http418, Http421, Http422, Http423,
  Http424, Http425, Http426, Http428, Http429, Http431, Http451,
  Http500, Http501, Http502, Http503, Http504, Http505, Http506, Http507, Http508, Http510, Http511

proc addBrandingHeaders(ctx: Context): Future[void] {.async, gcsafe.} =
  discard ctx.setHeader("X-Powered-By", "Rakta")
  discard ctx.setHeader("X-Rakta-Version", "0.2.0")
  await ctx.next()

proc executeMiddlewares(ctx: Context): Future[void] {.async, gcsafe.} =
  # Execute global middlewares
  if ctx.middlewareIndex < ctx.app.middlewares.len:
    let middleware = ctx.app.middlewares[ctx.middlewareIndex]
    ctx.middlewareIndex += 1
    ctx.nextCalled = false
    await middleware(ctx)
    if ctx.nextCalled:
      await executeMiddlewares(ctx)

proc executePathMiddlewares(ctx: Context, pathMiddlewares: seq[Handler]): Future[void] {.async, gcsafe.} =
  # Execute path-specific middlewares
  if ctx.pathMiddlewareIndex < pathMiddlewares.len:
    let middleware = pathMiddlewares[ctx.pathMiddlewareIndex]
    ctx.pathMiddlewareIndex += 1
    ctx.nextCalled = false
    await middleware(ctx)
    if ctx.nextCalled:
      await executePathMiddlewares(ctx, pathMiddlewares)

proc executeRouteMiddlewares(ctx: Context): Future[void] {.async, gcsafe.} =
  # Execute route-specific middlewares
  var routeMiddlewareIndex = 0
  
  proc executeNext(): Future[void] {.async, gcsafe.} =
    if routeMiddlewareIndex < ctx.routeMiddlewares.len:
      let middleware = ctx.routeMiddlewares[routeMiddlewareIndex]
      routeMiddlewareIndex += 1
      ctx.nextCalled = false
      await middleware(ctx)
      if ctx.nextCalled:
        await executeNext()
  
  await executeNext()

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
  
# Nim cannot do optional parameters or default values on varargs
# So, the proc overload method can handle this for us.

proc get*(app: App, pattern: string, handlers: varargs[Handler]) =
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
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpGet, pattern, routeHandler, middlewares)

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

proc post*(app: App, pattern: string, handlers: varargs[Handler]) =
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
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpPost, pattern, routeHandler, middlewares)

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

proc patch*(app: App, pattern: string, handlers: varargs[Handler]) =
  ## PATCH method implementation
  ## Registers a PATCH route handler with optional middlewares
  ## PATCH is typically used for partial updates to resources
  ##
  ## Parameters:
  ##   app: The application instance
  ##   pattern: URL pattern (supports path parameters like "/users/:id")
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##            and preceding ones are middlewares
  ##
  ## Example:
  ##   ```nim
  ##   app.patch("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     # Handle partial user update
  ##     let userId = ctx.params["id"]
  ##     await ctx.json(%*{"updated": true, "id": userId})
  ##   )
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpPatch, pattern, routeHandler, middlewares)
  
proc patch*(app: App, pattern: string, handler: Handler) =
  ## PATCH method implementation
  ## Registers a PATCH route handler with optional middlewares
  ## PATCH is typically used for partial updates to resources
  ##
  ## Parameters:
  ##   app: The application instance
  ##   pattern: URL pattern (supports path parameters like "/users/:id")
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##            and preceding ones are middlewares
  ##
  ## Example:
  ##   ```nim
  ##   app.patch("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     # Handle partial user update
  ##     let userId = ctx.params["id"]
  ##     await ctx.json(%*{"updated": true, "id": userId})
  ##   )
  ##   ```
  app.addRoute(HttpPatch, pattern, handler)

proc head*(app: App, pattern: string, handlers: varargs[Handler]) =
  ## Registers a HEAD route handler for the specified pattern.
  ## 
  ## HEAD method is identical to GET except that the server MUST NOT
  ## return a message-body in the response. This is useful for retrieving
  ## meta-information about the resource without transferring the actual content.
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/api/users/:id", "/health")
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##            and preceding ones are middlewares
  ## 
  ## Example:
  ##   ```nim
  ##   app.head("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.getParam("id")
  ##     # Set appropriate headers
  ##     discard ctx.setHeader("Content-Type", "application/json")
  ##     discard ctx.setHeader("Content-Length", "156")
  ##     # End without body
  ##     await ctx.endRes()
  ##   )
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpHead, pattern, routeHandler, middlewares)

proc head*(app: App, pattern: string, handler: Handler) =
  ## Registers a HEAD route handler for the specified pattern.
  ## 
  ## HEAD method is identical to GET except that the server MUST NOT
  ## return a message-body in the response. This is useful for retrieving
  ## meta-information about the resource without transferring the actual content.
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (e.g., "/api/users/:id", "/health")
  ##   handler: Async function to handle the request
  ## 
  ## Example:
  ##   ```nim
  ##   app.head("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.getParam("id")
  ##     # Set appropriate headers
  ##     discard ctx.setHeader("Content-Type", "application/json")
  ##     discard ctx.setHeader("Content-Length", "156")
  ##     # End without body
  ##     await ctx.endRes()
  ##   )
  ##   ```
  app.addRoute(HttpHead, pattern, handler)

proc put*(app: App, pattern: string, handlers: varargs[Handler]) =
  ## Registers a PUT route handler with optional middlewares.
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
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpPut, pattern, routeHandler, middlewares)
  
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

proc delete*(app: App, pattern: string, handlers: varargs[Handler]) =
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
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  app.addRoute(HttpDelete, pattern, routeHandler, middlewares)
  
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
  ## Adds a global middleware function to the application.
  ## 
  ## Global middleware functions are executed for all routes.
  ## 
  ## Parameters:
  ##   middleware: Async middleware function that processes Context
  ## 
  ## Example:
  ##   ```nim
  ##   app.use(corsMiddleware())
  ##   app.use(proc(ctx: Context): Future[void] {.async.} =
  ##     echo "Request to ", ctx.req.path
  ##     await ctx.next()
  ##   )
  ##   ```
  app.middlewares.add(middleware)

proc use*(app: App, pattern: string, middlewares: varargs[Handler]) =
  ## Adds path-specific middleware functions to the application.
  ## 
  ## Path-specific middleware functions are executed only for routes
  ## that match the specified pattern.
  ## 
  ## Parameters:
  ##   pattern: URL pattern to match (supports parameters like "/admin/:id")
  ##   middlewares: Variable number of middleware functions
  ## 
  ## Example:
  ##   ```nim
  ##   # Single middleware for admin routes
  ##   app.use("/admin", authMiddleware)
  ##   
  ##   # Multiple middlewares for API routes
  ##   app.use("/api", corsMiddleware, rateLimiter, loggingMiddleware)
  ##   ```
  for middleware in middlewares:
    let pathMiddleware = createPathMiddleware(pattern, middleware)
    app.pathMiddlewares.add(pathMiddleware)

proc handleRequest(app: App, httpReq: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
  var fullUrl = httpReq.url.path
  if httpReq.url.query.len > 0:
    fullUrl = fullUrl & "?" & httpReq.url.query
  
  let req = newRequest(httpReq.reqMethod, fullUrl, httpReq.headers, httpReq.body)
  let res = newResponse()
  let ctx = newContext(req, res, app)
  
  try:
    # Execute global middlewares
    await executeMiddlewares(ctx)
    
    if not ctx.res.sent:
      let matchingPathMiddlewares = getMatchingPathMiddlewares(app, ctx.req.path)
      
      if matchingPathMiddlewares.len > 0:
        await executePathMiddlewares(ctx, matchingPathMiddlewares)
      
      if not ctx.res.sent:
        let (route, params) = app.findRoute(ctx.req.httpMethod, ctx.req.path)
        if route != nil:
          ctx.params = params
          ctx.routeMiddlewares = route.middlewares

          if ctx.routeMiddlewares.len > 0:
            await executeRouteMiddlewares(ctx)

          if not ctx.res.sent:
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