import asyncdispatch, json
import Rakta

let appEg = newApp()

appEg.use(corsMiddleware())
appEg.use(serveStatic("public"))

appEg.use(proc(ctx: Context): Future[void] {.async.} =
  echo "Incoming request to ", ctx.req.path
  await ctx.next()
)

appEg.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{"message": "Welcome to Rakta"})
)

appEg.get("/user/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{"userId": userId, "message": "User profile"})
)

appEg.get("/hello", proc(ctx: Context): Future[void] {.async.} =
  let name = ctx.getQuery("name")
  if name != "":
    await ctx.json(%*{"message": "Hello, " & name & "!"})
  else:
    await ctx.json(%*{"message": "Hello, World!"})
)

appEg.post("/api/data", proc(ctx: Context): Future[void] {.async.} =
  let jsonData = ctx.jsonBody()
  await ctx.json(%*{"received": jsonData, "status": "success"})
)

appEg.get("/cookie-test", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.setCookie("test-cookie", "rakta-value")
  await ctx.json(%*{"message": "Cookie set!"})
)

appEg.get("/read-cookie", proc(ctx: Context): Future[void] {.async.} =
  let cookieValue = ctx.getCookie("test-cookie")
  await ctx.json(%*{"cookieValue": cookieValue})
)

waitFor appEg.listen(3000, proc() =
  echo "🚀 Server running at http://localhost:3000"
)