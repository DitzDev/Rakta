import asyncdispatch, json
import Rakta
import routes/api_routes

let app = newApp()

app.use(proc(ctx: Context): Future[void] {.async.} =
  echo "Global middleware: ", ctx.req.path
  await ctx.next()
)

app.use("/api", apiRouter())

app.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.send("Welcome to Rakta with Modular Routing!")
)

app.get("/health", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{"status": "ok", "timestamp": "2024-01-01"})
)

waitFor app.listen(3000, proc() =
  echo "Server running at http://localhost:3000"
)