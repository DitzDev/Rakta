import Rakta, asyncdispatch, json

let app = newApp()
# define port
let PORT = 3000

app.get("/json", proc(ctx: Context): Future[void] {.async.} = 
  await ctx.json(%*{"message": "Hello, World!"})
  await ctx.endRes()
)

app.head("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  discard ctx.setHeader("Content-Type", "application/json")
  discard ctx.setHeader("Content-Length", "156")
  await ctx.endRes()
)

waitFor app.listen(PORT, proc() =
  echo "Server running on PORT: ", PORT
)