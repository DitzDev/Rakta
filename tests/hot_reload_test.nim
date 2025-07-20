import Rakta, asyncdispatch, json, times

let app = newApp()

# Middleware
app.use(corsMiddleware())
app.use(app.serveStatic("public", "/public"))

app.useExperimentalFEHotReload(@["public"])
# Define port
let port = 8080

# Routes
app.get("/", proc(ctx: Context): Future[void] {.async.} =
   await ctx.sendFile("index.html")
)

app.get("/api/status", proc(ctx: Context): Future[void] {.async.} =
   await ctx.json(%*{
     "status": "ok", 
     "hotReload": "enabled",
     "timestamp": $now()
   })
)

# Start server
waitFor app.listen(port, proc() =
  echo "🚀 Server listening on PORT: ", port
  echo "📁 Hot Reload watching for file changes..."
  echo "🔥 Edit files in 'public' directory to see hot reload in action!"
)