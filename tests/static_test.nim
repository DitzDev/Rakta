import Rakta, asyncdispatch

let app = newApp()

app.use(corsMiddleware())
app.use(app.serveStatic("public", "/public"))

# Define port
let port = 8080

waitFor app.listen(port, proc() =
  echo "Server listening on PORT: ", port
)