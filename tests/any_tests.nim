import Rakta, asyncdispatch, json

let app = newApp()
# define port
let PORT = 8080

app.get("/sample/error", proc(ctx: Context): Future[void] {.async.} = 
  discard ctx.status(Http400)
  await ctx.json(%*{
    "error": "This is a demo error",
    "code": 400,
    "message": "Bad Request - This is intentional for demo purposes"
  })
)

waitFor app.listen(PORT, proc() =
  echo "Server running on PORT: ", PORT
)