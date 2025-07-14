import asyncdispatch, httpcore, strutils
import types, response, context

proc corsMiddleware*(allowOrigin: string = "*", allowMethods: string = "GET,POST,PUT,DELETE", allowHeaders: string = "Content-Type"): Handler =
  return proc(ctx: Context): Future[void] {.async.} =
    discard ctx.setHeader("Access-Control-Allow-Origin", allowOrigin)
    discard ctx.setHeader("Access-Control-Allow-Methods", allowMethods)
    discard ctx.setHeader("Access-Control-Allow-Headers", allowHeaders)
    
    if ctx.req.httpMethod == HttpOptions:
      discard ctx.status(Http200)
      await ctx.send("")
      return
    
    await ctx.next()