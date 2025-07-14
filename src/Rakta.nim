import asyncdispatch, asynchttpserver, httpcore, strutils, uri
import Rakta/types, Rakta/router, Rakta/response, Rakta/context, Rakta/cors, Rakta/static

export types, response, context, cors, static

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
  result = App(
    routes: @[],
    middlewares: @[],
    port: 3000
  )
  # Add default branding middleware
  result.middlewares.add(addBrandingHeaders)

proc get*(app: App, pattern: string, handler: Handler) =
  app.addRoute(HttpGet, pattern, handler)

proc post*(app: App, pattern: string, handler: Handler) =
  app.addRoute(HttpPost, pattern, handler)

proc put*(app: App, pattern: string, handler: Handler) =
  app.addRoute(HttpPut, pattern, handler)

proc delete*(app: App, pattern: string, handler: Handler) =
  app.addRoute(HttpDelete, pattern, handler)

proc use*(app: App, middleware: Handler) =
  app.middlewares.add(middleware)

proc handleRequest(app: App, httpReq: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
  let req = newRequest(httpReq.reqMethod, httpReq.url.path, httpReq.headers, httpReq.body)
  let res = newResponse()
  let ctx = newContext(req, res, app)
  
  try:
    # Execute middlewares first
    await executeMiddlewares(ctx)
    
    # If response wasn't sent by middleware, try to find and execute route
    if not ctx.res.sent:
      let (route, params) = app.findRoute(ctx.req.httpMethod, ctx.req.path)
      if route != nil:
        ctx.params = params
        await route.handler(ctx)
      else:
        discard ctx.status(Http404)
        await ctx.send("Not Found")
    
    # Send response
    await httpReq.respond(ctx.res.status, ctx.res.body, ctx.res.headers)
  except Exception as e:
    echo "Error handling request: ", e.msg
    await httpReq.respond(Http500, "Internal Server Error")

proc listen*(app: App, port: int, callback: proc() = nil) {.async.} =
  app.port = port
  let server = newAsyncHttpServer()
  
  proc handleRequestWrapper(req: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
    await app.handleRequest(req)
  
  if callback != nil:
    callback()
  
  await server.serve(Port(port), handleRequestWrapper)