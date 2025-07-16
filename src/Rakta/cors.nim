import asyncdispatch, httpcore, strutils
import types, response, context

proc corsMiddleware*(allowOrigin: string = "*", allowMethods: string = "GET,HEAD,PUT,PATCH,POST,DELETE", allowHeaders: string = "Content-Type"): Handler =
  ## Creates a CORS (Cross-Origin Resource Sharing) middleware.
  ## 
  ## This middleware adds CORS headers to responses, allowing cross-origin
  ## requests from web browsers. It handles preflight OPTIONS requests
  ## automatically and adds the necessary headers to all responses.
  ## 
  ## Parameters:
  ##   allowOrigin: Allowed origins for CORS requests (default: "*" for all origins)
  ##   allowMethods: Allowed HTTP methods (default: "GET,HEAD,PUT,PATCH,POST,DELETE")
  ##   allowHeaders: Allowed headers in requests (default: "Content-Type")
  ## 
  ## Returns:
  ##   Handler: Middleware function that adds CORS headers
  ## 
  ## Example:
  ##   ```nim
  ##   # Allow all origins
  ##   app.use(corsMiddleware())
  ##   
  ##   # Allow specific origin
  ##   app.use(corsMiddleware("https://myapp.com"))
  ##   
  ##   # Custom configuration
  ##   app.use(corsMiddleware(
  ##     allowOrigin = "https://myapp.com",
  ##     allowMethods = "GET,POST,PUT,DELETE",
  ##     allowHeaders = "Content-Type,Authorization"
  ##   ))
  ##   ```
  return proc(ctx: Context): Future[void] {.async.} =
    discard ctx.setHeader("Access-Control-Allow-Origin", allowOrigin)
    discard ctx.setHeader("Access-Control-Allow-Methods", allowMethods)
    discard ctx.setHeader("Access-Control-Allow-Headers", allowHeaders)
    
    if ctx.req.httpMethod == HttpOptions:
      discard ctx.status(Http200)
      await ctx.send("")
      return
    
    await ctx.next()