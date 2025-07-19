import asyncdispatch, json
import Rakta

proc apiRouter*(): Router =
  let apiRoute = newRouter()
  
  apiRoute.use(proc(ctx: Context): Future[void] {.async.} =
    echo "API Router middleware: ", ctx.req.path
    discard ctx.setHeader("X-API-Version", "1.0")
    await ctx.next()
  )
  
  apiRoute.get("/users", proc(ctx: Context): Future[void] {.async.} =
    await ctx.json(%*{
      "users": [
        {"id": 1, "name": "John Doe"},
        {"id": 2, "name": "Jane Smith"}
      ]
    })
  )
  
  apiRoute.get("/users/:id", proc(ctx: Context): Future[void] {.async.} =
    let userId = ctx.getParam("id")
    await ctx.json(%*{
      "user": {"id": userId, "name": "User " & userId}
    })
  )
  
  apiRoute.post("/users", proc(ctx: Context): Future[void] {.async.} =
    await ctx.json(%*{
      "message": "User created successfully",
      "id": 123
    })
  )
  
  apiRoute.put("/users/:id", proc(ctx: Context): Future[void] {.async.} =
    let userId = ctx.getParam("id")
    await ctx.json(%*{
      "message": "User " & userId & " updated successfully"
    })
  )
  
  apiRoute.delete("/users/:id", proc(ctx: Context): Future[void] {.async.} =
    let userId = ctx.getParam("id")
    await ctx.json(%*{
      "message": "User " & userId & " deleted successfully"
    })
  )
  
  apiRoute.use("/protected", proc(ctx: Context): Future[void] {.async, closure.} =
    if ctx.getHeader("Authorization") == "":
      discard ctx.status(Http401)
      await ctx.json(%*{"error": "Unauthorized"})
      return
    await ctx.next()
  )
  
  apiRoute.get("/protected/profile", proc(ctx: Context): Future[void] {.async.} =
    await ctx.json(%*{
      "profile": {
        "id": 1,
        "name": "Protected User",
        "email": "user@example.com",
        "role": "admin"
      }
    })
  )
  
  apiRoute.get("/protected/settings", proc(ctx: Context): Future[void] {.async.} =
    await ctx.json(%*{
      "settings": {
        "theme": "dark",
        "notifications": true,
        "language": "en"
      }
    })
  )
  
  return apiRoute