import asyncdispatch, json, os, times, tables, httpcore
import Rakta

let appEg = newApp()

appEg.use(corsMiddleware())
appEg.use(appEg.serveStatic("public"))

appEg.use(proc(ctx: Context): Future[void] {.async.} =
  echo "Incoming request to ", ctx.req.path
  await ctx.next()
)

appEg.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.sendFile("index.html")
)

appEg.get("/test-cors", proc(ctx: Context): Future[void] {.async.} =
  await ctx.sendFile("public/tests/test_cors.html")
)

appEg.get("/api/status", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "status": "success",
    "framework": "Rakta",
    "version": "0.1.0",
    "timestamp": $now(),
    "endpoints": [
      "/api/status",
      "/api/users/:id",
      "/api/hello",
      "/api/data"
    ]
  })
)

appEg.get("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{
    "userId": userId,
    "name": "User " & userId,
    "email": "user" & userId & "@example.com",
    "status": "active",
    "joinDate": "2024-01-01"
  })
)

appEg.get("/api/hello", proc(ctx: Context): Future[void] {.async.} =
  let name = ctx.getQuery("name")
  let lang = ctx.getQuery("lang")
  
  var greeting = "Hello"
  case lang:
  of "id": greeting = "Halo"
  of "es": greeting = "Hola"
  of "fr": greeting = "Bonjour"
  of "de": greeting = "Hallo"
  of "ja": greeting = "こんにちは"
  else: greeting = "Hello"
  
  if name != "":
    await ctx.json(%*{
      "message": greeting & ", " & name & "!",
      "language": lang,
      "timestamp": $now()
    })
  else:
    await ctx.json(%*{
      "message": greeting & ", World!",
      "language": lang,
      "timestamp": $now()
    })
)

appEg.post("/api/data", proc(ctx: Context): Future[void] {.async.} =
  let jsonData = ctx.jsonBody()
  await ctx.json(%*{
    "received": jsonData,
    "status": "success",
    "processed_at": $now(),
    "server": "Rakta Framework"
  })
)

appEg.get("/api/demo-data", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "users": [
      {"id": 1, "name": "Alice Johnson", "role": "Admin"},
      {"id": 2, "name": "Bob Smith", "role": "User"},
      {"id": 3, "name": "Charlie Brown", "role": "Moderator"}
    ],
    "stats": {
      "totalUsers": 3,
      "activeUsers": 2,
      "serverUptime": "2 hours"
    }
  })
)

appEg.get("/download/sample.pdf", proc(ctx: Context): Future[void] {.async.} =
  let customHeaders = {
    "Content-Disposition": "attachment; filename=sample.pdf",
    "X-Custom-Header": "Rakta Framework Sample"
  }.toTable()
  await ctx.sendFile("public/sample.pdf", customHeaders)
)

appEg.get("/download/image/:name", proc(ctx: Context): Future[void] {.async.} =
  let imageName = ctx.getParam("name")
  await ctx.sendFile("public/images/" & imageName)
)

appEg.get("/api/cookie/set", proc(ctx: Context): Future[void] {.async.} =
  let value = ctx.getQuery("value")
  discard ctx.setCookie("rakta-demo", if value != "": value else: "default-value")
  await ctx.json(%*{
    "message": "Cookie set successfully!",
    "value": if value != "": value else: "default-value"
  })
)

appEg.get("/api/cookie/get", proc(ctx: Context): Future[void] {.async.} =
  let cookieValue = ctx.getCookie("rakta-demo")
  await ctx.json(%*{
    "cookieValue": if cookieValue != "": cookieValue else: "No cookie found",
    "hasCookie": cookieValue != ""
  })
)


appEg.get("/api/error", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.status(Http400)
  await ctx.json(%*{
    "error": "This is a demo error",
    "code": 400,
    "message": "Bad Request - This is intentional for demo purposes"
  })
)

if not dirExists("public"):
  createDir("public")
if not dirExists("public/images"):
  createDir("public/images")

waitFor appEg.listen(3000, proc() =
  echo "🚀 Rakta Framework Server running at http://localhost:3000"
  echo "📁 Serving static files from 'public' directory"
  echo "🔧 API endpoints available at /api/*"
)