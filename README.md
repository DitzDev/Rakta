<p align="center">
  <img src="assets/rakta_logo.png" alt="Rakta Logo" height="100">
</p>

<h1 align="center">Rakta</h1>

<p align="center">
  <b>Express.js like, Powerful, Fast, and Minimalist Web Framework for Nim</b>  
  <br>
  <i>Focus on your backend.</i>
</p>

<p align="center">
  <a href="https://github.com/DitzDev/Rakta/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/DitzDev/rakta?color=blue" alt="License">
  </a>
</p>

> [!WARNING]
> This project is still in development stage.

## Features

- **Fast & Efficient**: Built with Nim's performance in mind
- **Minimalist Design**: Clean API with essential features
- **Middleware Support**: Flexible middleware system
- **Static File Serving**: Built-in static file serving with caching
- **CORS Support**: Easy cross-origin resource sharing setup
- **Route Parameters**: Support for dynamic route parameters
- **JSON Support**: Built-in JSON request/response handling
- **Cookie Management**: Easy cookie setting and retrieval
- **File Upload**: Support for file uploads and downloads

## Installation

```bash
nimble install rakta
```

## Quick Start

```nim
import asyncdispatch, json
import Rakta

let app = newApp()

# Add CORS middleware
app.use(corsMiddleware())

# Serve static files
app.use(app.serveStatic("public"))

# Basic route
app.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.send("Hello, Rakta!")
)

# JSON API endpoint
app.get("/api/status", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "status": "success",
    "framework": "Rakta",
    "version": "0.1.0"
  })
)

# Route with parameters
app.get("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{
    "userId": userId,
    "name": "User " & userId
  })
)

# Start server
waitFor app.listen(3000, proc() =
  echo "🚀 Server running at http://localhost:3000"
)
```

## Documentation

### Application Setup

#### Creating an App

```nim
let app = newApp()
```

Creates a new Rakta application instance with default configuration.

#### Starting the Server

```nim
waitFor app.listen(3000, proc() =
  echo "Server started on port 3000"
)
```

Starts the HTTP server on the specified port with an optional callback.

### Routing

#### Basic Routes

```nim
# GET route
app.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.send("Hello World")
)

# POST route
app.post("/api/users", proc(ctx: Context): Future[void] {.async.} =
  let userData = ctx.jsonBody()
  await ctx.json(%*{"created": userData})
)

# PUT route
app.put("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  let userData = ctx.jsonBody()
  await ctx.json(%*{"updated": userId, "data": userData})
)

# DELETE route
app.delete("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{"deleted": userId})
)
```

#### Route Parameters

```nim
# Single parameter
app.get("/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{"userId": userId})
)

# Multiple parameters
app.get("/posts/:category/:slug", proc(ctx: Context): Future[void] {.async.} =
  let category = ctx.getParam("category")
  let slug = ctx.getParam("slug")
  await ctx.json(%*{"category": category, "slug": slug})
)
```

### Middleware

#### Using Middleware

```nim
# Built-in CORS middleware
app.use(corsMiddleware())

# Custom middleware
app.use(proc(ctx: Context): Future[void] {.async.} =
  echo "Request to ", ctx.req.path
  await ctx.next()
)

# Static file serving
app.use(app.serveStatic("public"))
```

#### CORS Configuration

```nim
# Allow all origins
app.use(corsMiddleware())

# Allow specific origin
app.use(corsMiddleware("https://myapp.com"))

# Custom configuration
app.use(corsMiddleware(
  allowOrigin = "https://myapp.com",
  allowMethods = "GET,POST,PUT,DELETE",
  allowHeaders = "Content-Type,Authorization"
))
```

### Request Handling

#### Query Parameters

```nim
app.get("/search", proc(ctx: Context): Future[void] {.async.} =
  let query = ctx.getQuery("q")
  let page = ctx.getQuery("page")
  await ctx.json(%*{"query": query, "page": page})
)
```

#### JSON Request Body

```nim
app.post("/api/data", proc(ctx: Context): Future[void] {.async.} =
  let jsonData = ctx.jsonBody()
  await ctx.json(%*{"received": jsonData})
)
```

#### Cookies

```nim
# Set cookie
app.get("/login", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.setCookie("session", "abc123", httpOnly = true)
  await ctx.json(%*{"message": "Logged in"})
)

# Get cookie
app.get("/profile", proc(ctx: Context): Future[void] {.async.} =
  let sessionId = ctx.getCookie("session")
  if sessionId != "":
    await ctx.json(%*{"sessionId": sessionId})
  else:
    await ctx.json(%*{"error": "Not authenticated"})
)
```

### Response Handling

#### Plain Text Response

```nim
app.get("/text", proc(ctx: Context): Future[void] {.async.} =
  await ctx.send("Plain text response")
)
```

#### JSON Response

```nim
app.get("/json", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{"message": "JSON response"})
)
```

#### Custom Headers

```nim
app.get("/custom", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.setHeader("X-Custom-Header", "Custom Value")
  await ctx.send("Response with custom header")
)
```

#### Status Codes

```nim
app.get("/error", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.status(Http400)
  await ctx.json(%*{"error": "Bad Request"})
)
```

### File Handling

#### Serving Files

```nim
# Basic file serving
app.get("/download", proc(ctx: Context): Future[void] {.async.} =
  await ctx.sendFile("files/document.pdf")
)

# With custom headers
app.get("/download/pdf", proc(ctx: Context): Future[void] {.async.} =
  let headers = {
    "Content-Disposition": "attachment; filename=document.pdf"
  }.toTable()
  await ctx.sendFile("files/document.pdf", headers)
)
```

#### Static Files

```nim
# Serve from public directory
app.use(app.serveStatic("public"))

# Serve with URL prefix
app.use(app.serveStatic("assets", "/static"))
```

### Error Handling

```nim
app.get("/api/error", proc(ctx: Context): Future[void] {.async.} =
  try:
    # Some operation that might fail
    raise newException(ValueError, "Something went wrong")
  except ValueError as e:
    discard ctx.status(Http400)
    await ctx.json(%*{"error": e.msg})
)
```

## API Reference

### App Methods

- `newApp()`: Creates a new application instance
- `get(pattern, handler)`: Registers GET route
- `post(pattern, handler)`: Registers POST route
- `put(pattern, handler)`: Registers PUT route
- `delete(pattern, handler)`: Registers DELETE route
- `use(middleware)`: Adds middleware
- `serveStatic(dir, prefix)`: Creates static file middleware
- `listen(port, callback)`: Starts the server

### Context Methods

- `getParam(name)`: Gets route parameter value
- `getQuery(name)`: Gets query parameter value
- `getCookie(name)`: Gets cookie value
- `jsonBody()`: Parses request body as JSON
- `send(content)`: Sends plain text response
- `json(data)`: Sends JSON response
- `sendFile(path, options)`: Sends file response
- `status(code)`: Sets response status code
- `setHeader(name, value)`: Sets response header
- `setCookie(name, value, options)`: Sets cookie
- `next()`: Continues to next middleware

### Middleware

- `corsMiddleware(origin, methods, headers)`: CORS middleware
- `serveStatic(dir, prefix)`: Static file serving middleware

## Examples

### Complete API Server

```nim
import asyncdispatch, json, os, times, tables
import Rakta

let app = newApp()

# Middleware
app.use(corsMiddleware())
app.use(app.serveStatic("public"))

# Logging middleware
app.use(proc(ctx: Context): Future[void] {.async.} =
  echo "Incoming request to ", ctx.req.path
  await ctx.next()
)

# API routes
app.get("/api/status", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "status": "success",
    "framework": "Rakta",
    "version": "0.1.0",
    "timestamp": $now()
  })
)

app.get("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  await ctx.json(%*{
    "userId": userId,
    "name": "User " & userId,
    "email": "user" & userId & "@example.com"
  })
)

app.post("/api/users", proc(ctx: Context): Future[void] {.async.} =
  let userData = ctx.jsonBody()
  await ctx.json(%*{
    "created": userData,
    "id": "new-user-id",
    "timestamp": $now()
  })
)

# File operations
app.get("/download/:file", proc(ctx: Context): Future[void] {.async.} =
  let filename = ctx.getParam("file")
  await ctx.sendFile("files/" & filename)
)

# Error handling
app.get("/api/error", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.status(Http400)
  await ctx.json(%*{
    "error": "This is a demo error",
    "code": 400
  })
)

# Start server
waitFor app.listen(3000, proc() =
  echo "🚀 Rakta Framework Server running at http://localhost:3000"
)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License
```
MIT License

Copyright (c) 2025 DitzDev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
