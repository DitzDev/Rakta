import httpcore, strutils
import ../types, ../router, ../middleware 

proc createRoute(httpMethod: HttpMethod, pattern: string, handler: Handler, middlewares: seq[Handler] = @[]): Route =
  let isExact = not pattern.contains(':')
  
  return Route(
    httpMethod: httpMethod,
    pattern: pattern,
    handler: handler,
    middlewares: middlewares,
    paramNames: if isExact: @[] else: extractParamNames(pattern),
    compiledRegex: if isExact: nil else: patternToRegex(pattern),
    isExact: isExact
  )

proc combinePaths(prefix: string, path: string): string =
  var cleanPrefix = prefix
  var cleanPath = path

  if cleanPrefix.endsWith("/") and cleanPrefix.len > 1:
    cleanPrefix = cleanPrefix[0..^2]
  
  if not cleanPath.startsWith("/"):
    cleanPath = "/" & cleanPath

  if cleanPrefix == "" or cleanPrefix == "/":
    return cleanPath
  
  return cleanPrefix & cleanPath

proc mountRouter*(app: App, prefix: string, router: Router) =
  for middleware in router.middlewares:
    let pathMiddleware = createPathMiddleware(prefix, middleware)
    app.pathMiddlewares.add(pathMiddleware)

  for pathMiddleware in router.pathMiddlewares:
    let newPattern = combinePaths(prefix, pathMiddleware.pattern)
    let newPathMiddleware = createPathMiddleware(newPattern, pathMiddleware.handler)
    app.pathMiddlewares.add(newPathMiddleware)

  for route in router.routes:
    let newPattern = combinePaths(prefix, route.pattern)
    app.addRoute(route.httpMethod, newPattern, route.handler, route.middlewares)

proc newRouter*(): Router =
  ## Creates a new Router instance for organizing routes modularly.
  ## 
  ## This allows you to create separate router instances for different
  ## parts of your API and then mount them to the main app.
  ## 
  ## Returns:
  ##   Router: A new router instance ready to be configured
  ## 
  ## Example:
  ##   ```nim
  ##   let apiRouter = newRouter()
  ##   apiRouter.get("/users", getUsersHandler)
  ##   apiRouter.post("/users", createUserHandler)
  ##   
  ##   # Mount to main app
  ##   app.use("/api", apiRouter)
  ##   ```
  result = Router(
    routes: @[],
    middlewares: @[],
    pathMiddlewares: @[],
    prefix: ""
  )

# Router HTTP methods
proc get*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a GET route handler on the router with optional middlewares.
  ## 
  ## GET routes are used for retrieving data from the server. They should be
  ## idempotent and safe operations that don't modify server state.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Simple GET route
  ##   router.get("/users", getUsersHandler)
  ##   
  ##   # GET route with middlewares
  ##   router.get("/users/:id", authMiddleware, validateIdMiddleware, getUserHandler)
  ##   
  ##   # GET route with path parameters
  ##   router.get("/users/:id/posts/:postId", getUserPostHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpGet, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc get*(router: Router, pattern: string, handler: Handler) =
  ## Registers a GET route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## GET routes are used for retrieving data and should be idempotent.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.get("/", proc(ctx: Context): Future[void] {.async.} =
  ##     await ctx.json(%*{"message": "Hello World"})
  ##   )
  ##   
  ##   router.get("/users/:id", getUserByIdHandler)
  ##   ```
  let route = createRoute(HttpGet, pattern, handler)
  router.routes.add(route)

proc post*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a POST route handler on the router with optional middlewares.
  ## 
  ## POST routes are used for creating new resources or submitting data to the server.
  ## They are not idempotent and can modify server state.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Simple POST route
  ##   router.post("/users", createUserHandler)
  ##   
  ##   # POST route with validation middleware
  ##   router.post("/users", validateUserMiddleware, createUserHandler)
  ##   
  ##   # POST route for nested resources
  ##   router.post("/users/:id/posts", authMiddleware, createUserPostHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpPost, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc post*(router: Router, pattern: string, handler: Handler) =
  ## Registers a POST route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## POST routes are used for creating resources and submitting data.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.post("/login", proc(ctx: Context): Future[void] {.async.} =
  ##     let body = await ctx.req.body()
  ##     # Process login logic
  ##     await ctx.json(%*{"token": "jwt_token_here"})
  ##   )
  ##   ```
  let route = createRoute(HttpPost, pattern, handler)
  router.routes.add(route)

proc put*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a PUT route handler on the router with optional middlewares.
  ## 
  ## PUT routes are used for updating entire resources or creating resources
  ## at specific URIs. They should be idempotent.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Update user resource
  ##   router.put("/users/:id", authMiddleware, validateUserMiddleware, updateUserHandler)
  ##   
  ##   # Replace entire resource
  ##   router.put("/posts/:id", authMiddleware, replacePostHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpPut, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc put*(router: Router, pattern: string, handler: Handler) =
  ## Registers a PUT route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## PUT routes are used for updating entire resources and should be idempotent.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.put("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.pathParams["id"]
  ##     let body = await ctx.req.body()
  ##     # Update user logic
  ##     await ctx.json(%*{"message": "User updated"})
  ##   )
  ##   ```
  let route = createRoute(HttpPut, pattern, handler)
  router.routes.add(route)

proc patch*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a PATCH route handler on the router with optional middlewares.
  ## 
  ## PATCH routes are used for partial updates of resources. Unlike PUT,
  ## PATCH only modifies the specified fields of a resource.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Partial update of user
  ##   router.patch("/users/:id", authMiddleware, patchUserHandler)
  ##   
  ##   # Update specific fields
  ##   router.patch("/posts/:id/status", authMiddleware, updatePostStatusHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpPatch, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc patch*(router: Router, pattern: string, handler: Handler) =
  ## Registers a PATCH route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## PATCH routes are used for partial updates of resources.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.patch("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.pathParams["id"]
  ##     let updates = await ctx.req.body()
  ##     # Apply partial updates
  ##     await ctx.json(%*{"message": "User partially updated"})
  ##   )
  ##   ```
  let route = createRoute(HttpPatch, pattern, handler)
  router.routes.add(route)

proc delete*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a DELETE route handler on the router with optional middlewares.
  ## 
  ## DELETE routes are used for removing resources from the server.
  ## They should be idempotent - multiple DELETE requests should have the same effect.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Delete user with authorization
  ##   router.delete("/users/:id", authMiddleware, adminMiddleware, deleteUserHandler)
  ##   
  ##   # Soft delete with confirmation
  ##   router.delete("/posts/:id", authMiddleware, confirmDeleteMiddleware, deletePostHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpDelete, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc delete*(router: Router, pattern: string, handler: Handler) =
  ## Registers a DELETE route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## DELETE routes are used for removing resources and should be idempotent.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.delete("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  ##     let userId = ctx.pathParams["id"]
  ##     # Delete user logic
  ##     await ctx.json(%*{"message": "User deleted"})
  ##   )
  ##   ```
  let route = createRoute(HttpDelete, pattern, handler)
  router.routes.add(route)

proc head*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a HEAD route handler on the router with optional middlewares.
  ## 
  ## HEAD routes are identical to GET requests but only return headers without the response body.
  ## They're useful for checking resource metadata, existence, or caching information.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # Check if resource exists
  ##   router.head("/files/:filename", authMiddleware, checkFileExistsHandler)
  ##   
  ##   # Get metadata without content
  ##   router.head("/users/:id", cacheMiddleware, getUserMetadataHandler)
  ##   ```
  if handlers.len == 0:
    return
  
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  let route = createRoute(HttpHead, pattern, routeHandler, middlewares)
  router.routes.add(route)

proc head*(router: Router, pattern: string, handler: Handler) =
  ## Registers a HEAD route handler on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## HEAD routes return only headers without response body.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.head("/health", proc(ctx: Context): Future[void] {.async.} =
  ##     ctx.res.headers["X-Service-Status"] = "healthy"
  ##     await ctx.send("")  # Empty body for HEAD requests
  ##   )
  ##   ```
  let route = createRoute(HttpHead, pattern, handler)
  router.routes.add(route)

proc all*(router: Router, pattern: string, handlers: varargs[Handler]) =
  ## Registers a route handler for ALL HTTP methods on the router with optional middlewares.
  ## 
  ## This creates routes that respond to any HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD).
  ## Useful for middleware that should run regardless of the HTTP method or for catch-all routes.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handlers: Variable number of handlers where the last one is the route handler
  ##             and preceding ones are middlewares specific to this route
  ## 
  ## Example:
  ##   ```nim
  ##   # CORS middleware for all methods
  ##   router.all("/api/*", corsMiddleware, handleApiRequest)
  ##   
  ##   # Logging for all requests to admin area
  ##   router.all("/admin/*", loggingMiddleware, authMiddleware, adminHandler)
  ##   ```
  if handlers.len == 0:
    return
    
  let routeHandler = handlers[handlers.len - 1]
  let middlewares = if handlers.len > 1: handlers[0..handlers.len-2] else: @[]
  
  # Register the same route for all HTTP methods
  let httpMethods = [HttpGet, HttpPost, HttpPut, HttpPatch, HttpDelete, HttpHead]
  for httpMethod in httpMethods:
    let route = createRoute(httpMethod, pattern, routeHandler, middlewares)
    router.routes.add(route)

proc all*(router: Router, pattern: string, handler: Handler) =
  ## Registers a route handler for ALL HTTP methods on the router.
  ## 
  ## This is a simplified version for routes that don't require middlewares.
  ## Creates routes that respond to any HTTP method.
  ## 
  ## Parameters:
  ##   pattern: URL pattern for the route (supports path parameters with :name)
  ##   handler: Async handler function that processes the request
  ## 
  ## Example:
  ##   ```nim
  ##   router.all("/api/catch-all", proc(ctx: Context): Future[void] {.async.} =
  ##     let httpMethod = $ctx.req.httpMethod
  ##     await ctx.json(%*{
  ##       "message": "Handled " & httpMethod & " request",
  ##       "path": ctx.req.path
  ##     })
  ##   )
  ##   ```
  # Register the same route for all HTTP methods
  let httpMethods = [HttpGet, HttpPost, HttpPut, HttpPatch, HttpDelete, HttpHead]
  for httpMethod in httpMethods:
    let route = createRoute(httpMethod, pattern, handler)
    router.routes.add(route)

proc use*(router: Router, middleware: Handler) =
  ## Adds a middleware function to the router.
  ## 
  ## Router middleware functions are executed for all routes within this router.
  ## Middleware is executed in the order it was added using `use()`.
  ## 
  ## Parameters:
  ##   middleware: Async middleware function that processes Context and calls next()
  ## 
  ## Example:
  ##   ```nim
  ##   let apiRouter = newRouter()
  ##   
  ##   # Add authentication middleware to all routes in this router
  ##   apiRouter.use(authMiddleware)
  ##   
  ##   # Add logging middleware
  ##   apiRouter.use(proc(ctx: Context): Future[void] {.async.} =
  ##     echo "API request to ", ctx.req.path
  ##     await ctx.next()
  ##   )
  ##   
  ##   # Now all routes will go through auth and logging
  ##   apiRouter.get("/users", getUsersHandler)
  ##   apiRouter.post("/users", createUserHandler)
  ##   ```
  router.middlewares.add(middleware)

proc use*(router: Router, pattern: string, middlewares: varargs[Handler]) =
  ## Adds path-specific middlewares to the router.
  ## 
  ## These middlewares only execute for routes that match the specified pattern.
  ## This is useful for applying middleware to a subset of routes.
  ## 
  ## Parameters:
  ##   pattern: URL pattern that must match for middleware to execute
  ##   middlewares: One or more middleware functions to apply
  ## 
  ## Example:
  ##   ```nim
  ##   let router = newRouter()
  ##   
  ##   # Apply auth middleware only to admin routes
  ##   router.use("/admin/*", authMiddleware, adminAuthMiddleware)
  ##   
  ##   # Apply rate limiting to API routes
  ##   router.use("/api/*", rateLimitMiddleware)
  ##   
  ##   # These routes will inherit the appropriate middleware
  ##   router.get("/admin/users", getUsersHandler)      # Will use auth middleware
  ##   router.get("/api/posts", getPostsHandler)        # Will use rate limiting
  ##   router.get("/public/info", getInfoHandler)       # No extra middleware
  ##   ```
  for middleware in middlewares:
    let pathMiddleware = createPathMiddleware(pattern, middleware)
    router.pathMiddlewares.add(pathMiddleware)

proc use*(app: App, prefix: string, router: Router) =
  ## Mounts a router to the application with the specified prefix.
  ## 
  ## This allows you to organize routes into separate modules and
  ## mount them at different paths in your application. All routes
  ## in the router will be prefixed with the specified path.
  ## 
  ## Parameters:
  ##   prefix: URL prefix for all routes in this router (e.g., "/api", "/admin")
  ##   router: Router instance containing organized routes
  ## 
  ## Example:
  ##   ```nim
  ##   let apiRouter = newRouter()
  ##   apiRouter.get("/users", getUsersHandler)         # Will become /api/users
  ##   apiRouter.post("/users", createUserHandler)      # Will become /api/users
  ##   apiRouter.get("/posts/:id", getPostHandler)      # Will become /api/posts/:id
  ##   
  ##   let adminRouter = newRouter()
  ##   adminRouter.use(authMiddleware)                   # Auth for all admin routes
  ##   adminRouter.get("/dashboard", dashboardHandler)  # Will become /admin/dashboard
  ##   adminRouter.get("/users", adminUsersHandler)     # Will become /admin/users
  ##   
  ##   # Mount routers to main app
  ##   app.use("/api", apiRouter)      # All API routes under /api
  ##   app.use("/admin", adminRouter)  # All admin routes under /admin
  ##   ```
  mountRouter(app, prefix, router)

proc use*(app: App, router: Router) =
  ## Mounts a router to the application at the root level.
  ## 
  ## This is equivalent to app.use("", router) and mounts all
  ## router routes directly without any prefix. Routes keep their
  ## original paths.
  ## 
  ## Parameters:
  ##   router: Router instance containing organized routes
  ## 
  ## Example:
  ##   ```nim
  ##   let mainRouter = newRouter()
  ##   mainRouter.get("/", homeHandler)           # Will remain /
  ##   mainRouter.get("/about", aboutHandler)     # Will remain /about
  ##   mainRouter.get("/contact", contactHandler) # Will remain /contact
  ##   
  ##   let blogRouter = newRouter()
  ##   blogRouter.get("/blog", blogIndexHandler)  # Will remain /blog
  ##   blogRouter.get("/blog/:slug", blogPostHandler)  # Will remain /blog/:slug
  ##   
  ##   # Mount at root level
  ##   app.use(mainRouter)  # Routes: /, /about, /contact
  ##   app.use(blogRouter)  # Routes: /blog, /blog/:slug
  ##   ```
  mountRouter(app, "", router)