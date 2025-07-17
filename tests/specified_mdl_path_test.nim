import asyncdispatch, json, os, times, httpcore, strutils, sequtils
import Rakta

let app = newApp()

# ==================== MIDDLEWARE EXAMPLES ====================

proc loggingMiddleware(): Handler =
  proc(ctx: Context): Future[void] {.async, closure.} =
    let startTime = now()
    echo "[", $startTime, "] ", ctx.req.httpMethod, " ", ctx.req.path
    await ctx.next()
    let endTime = now()
    let duration = endTime - startTime
    echo "[", $endTime, "] Response sent in ", duration.inMilliseconds, "ms"

proc authMiddleware(): Handler =
  proc(ctx: Context): Future[void] {.async, closure.} =
    let authHeader = ctx.getHeader("Authorization")
    if authHeader == "":
      discard ctx.status(Http401)
      await ctx.json(%*{"error": "Authorization header required"})
      return
    if not authHeader.startsWith("Bearer "):
      discard ctx.status(Http401)
      await ctx.json(%*{"error": "Invalid authorization format"})
      return
    let token = authHeader[7..^1]
    if token != "valid-token-123":
      discard ctx.status(Http401)
      await ctx.json(%*{"error": "Invalid token"})
      return
    await ctx.next()

proc validateJSONMiddleware(): Handler =
  proc(ctx: Context): Future[void] {.async, closure.} =
    if ctx.req.httpMethod in [HttpPost, HttpPut, HttpPatch]:
      let contentType = ctx.getHeader("Content-Type")
      if contentType != "application/json":
        discard ctx.status(Http400)
        await ctx.json(%*{"error": "Content-Type must be application/json"})
        return
    await ctx.next()

# ==================== APPLY MIDDLEWARE ====================

app.use(corsMiddleware())
app.use(app.serveStatic("public"))
app.use(loggingMiddleware())

# ==================== BASIC ROUTES ====================

app.get("/", proc(ctx: Context): Future[void] {.async.} =
  await ctx.sendFile("index.html")
)

app.get("/health", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "status": "healthy",
    "timestamp": $now(),
    "uptime": "running",
    "framework": "Rakta",
    "version": "0.1.0"
  })
)

# ==================== USER MANAGEMENT API ====================

# Get all users with pagination
app.get("/api/users", proc(ctx: Context): Future[void] {.async.} =
  let page = ctx.getQuery("page")
  let limit = ctx.getQuery("limit")
  let search = ctx.getQuery("search")
  
  # Simulate database data
  var users = @[
    %*{"id": 1, "name": "Alice Johnson", "email": "alice@example.com", "role": "admin"},
    %*{"id": 2, "name": "Bob Smith", "email": "bob@example.com", "role": "user"},
    %*{"id": 3, "name": "Charlie Brown", "email": "charlie@example.com", "role": "moderator"},
    %*{"id": 4, "name": "Diana Prince", "email": "diana@example.com", "role": "user"},
    %*{"id": 5, "name": "Eve Wilson", "email": "eve@example.com", "role": "user"}
  ]
  
  # Filter by search if provided
  if search != "":
    users = users.filter(proc(u: JsonNode): bool =
      u["name"].getStr().toLowerAscii().contains(search.toLowerAscii()) or
      u["email"].getStr().toLowerAscii().contains(search.toLowerAscii())
    )
  
  await ctx.json(%*{
    "users": users,
    "pagination": {
      "page": page,
      "limit": limit,
      "total": users.len,
      "hasNext": false,
      "hasPrev": false
    }
  })
)

# Get user by ID
app.get("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  
  try:
    let id = parseInt(userId)
    if id <= 0:
      discard ctx.status(Http400)
      await ctx.json(%*{"error": "Invalid user ID"})
      return
    
    # Simulate user lookup
    await ctx.json(%*{
      "id": id,
      "name": "User " & $id,
      "email": "user" & $id & "@example.com",
      "role": if id == 1: "admin" else: "user",
      "profile": {
        "joinDate": "2024-01-01",
        "lastLogin": $now(),
        "isActive": true
      }
    })
  except ValueError:
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "User ID must be a number"})
)

# Create new user
app.post("/api/users", validateJSONMiddleware(), proc(ctx: Context): Future[void] {.async, closure.} =
  let userData = ctx.jsonBody()
  
  # Validate required fields
  if not userData.hasKey("name") or not userData.hasKey("email"):
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "Name and email are required"})
    return
  
  # Simulate user creation
  let newUser = %*{
    "id": 999,
    "name": userData["name"],
    "email": userData["email"],
    "role": (if "role" in userData: userData["role"] else: %"user"),
    "createdAt": $now(),
    "isActive": true
  }
  
  discard ctx.status(Http201)
  await ctx.json(%*{
    "message": "User created successfully",
    "user": newUser
  })
)

# Update user
app.put("/api/users/:id", validateJSONMiddleware(), proc(ctx: Context): Future[void] {.async, closure.} =
  let userId = ctx.getParam("id")
  let updateData = ctx.jsonBody()
  
  try:
    let id = parseInt(userId)
    
    await ctx.json(%*{
      "message": "User updated successfully",
      "user": {
        "id": id,
        "name": if updateData.hasKey("name"): updateData["name"] else: %("User " & $id),
        "email": if updateData.hasKey("email"): updateData["email"] else: %("user" & $id & "@example.com"),
        "role": if updateData.hasKey("role"): updateData["role"] else: %"user",
        "updatedAt": $now()
      }
    })
  except ValueError:
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "Invalid user ID"})
)

# Delete user
app.delete("/api/users/:id", proc(ctx: Context): Future[void] {.async.} =
  let userId = ctx.getParam("id")
  
  try:
    let id = parseInt(userId)
    await ctx.json(%*{
      "message": "User deleted successfully",
      "deletedId": id,
      "deletedAt": $now()
    })
  except ValueError:
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "Invalid user ID"})
)

# ==================== PROTECTED ROUTES ====================

# Protected dashboard route
app.get("/api/dashboard", authMiddleware(), proc(ctx: Context): Future[void] {.async, closure.} =
  await ctx.json(%*{
    "dashboard": {
      "totalUsers": 150,
      "activeUsers": 120,
      "newUsersToday": 5,
      "serverStats": {
        "cpuUsage": "45%",
        "memoryUsage": "60%",
        "diskUsage": "30%"
      },
      "recentActivities": [
        {"action": "User login", "user": "alice@example.com", "time": $now()},
        {"action": "New user registered", "user": "bob@example.com", "time": $now()}
      ]
    }
  })
)

# Protected admin routes
app.get("/api/admin/logs", authMiddleware(), proc(ctx: Context): Future[void] {.async, closure.} =
  let logType = ctx.getQuery("type")
  let limit = ctx.getQuery("limit")
  
  await ctx.json(%*{
    "logs": [
      {"level": "INFO", "message": "Server started", "timestamp": $now()},
      {"level": "WARN", "message": "Rate limit exceeded", "timestamp": $now()},
      {"level": "ERROR", "message": "Database connection failed", "timestamp": $now()}
    ],
    "filters": {
      "type": logType,
      "limit": limit
    }
  })
)

# ==================== FILE UPLOAD SIMULATION ====================

app.post("/api/upload", proc(ctx: Context): Future[void] {.async.} =
  # Simulate file upload
  let fileName = ctx.getQuery("filename")
  let fileSize = ctx.getQuery("size")
  
  await ctx.json(%*{
    "message": "File uploaded successfully",
    "file": {
      "name": fileName,
      "size": fileSize,
      "uploadedAt": $now(),
      "url": "/files/" & fileName
    }
  })
)

# ==================== SEARCH & FILTERING ====================

app.get("/api/search", proc(ctx: Context): Future[void] {.async.} =
  let query = ctx.getQuery("q")
  let category = ctx.getQuery("category")
  let sortBy = ctx.getQuery("sort")
  
  if query == "":
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "Search query is required"})
    return
  
  # Simulate search results
  await ctx.json(%*{
    "query": query,
    "category": category,
    "sortBy": sortBy,
    "results": [
      {"id": 1, "title": "Result 1", "type": "article", "relevance": 0.95},
      {"id": 2, "title": "Result 2", "type": "product", "relevance": 0.87},
      {"id": 3, "title": "Result 3", "type": "user", "relevance": 0.75}
    ],
    "totalFound": 3,
    "searchTime": "0.05s"
  })
)

# ==================== ANALYTICS & METRICS ====================

app.get("/api/analytics", proc(ctx: Context): Future[void] {.async.} =
  let period = ctx.getQuery("period")
  let metric = ctx.getQuery("metric")
  
  await ctx.json(%*{
    "period": period,
    "metric": metric,
    "data": [
      {"date": "2024-01-01", "value": 1250},
      {"date": "2024-01-02", "value": 1180},
      {"date": "2024-01-03", "value": 1420},
      {"date": "2024-01-04", "value": 1350},
      {"date": "2024-01-05", "value": 1580},
      {"date": "2024-01-06", "value": 1290},
      {"date": "2024-01-07", "value": 1650}
    ],
    "summary": {
      "total": 9720,
      "average": 1388,
      "growth": "+12.5%"
    }
  })
)

# ==================== WEBHOOKS ====================

app.post("/api/webhooks/payment", proc(ctx: Context): Future[void] {.async.} =
  let webhookData = ctx.jsonBody()
  
  # Simulate webhook processing
  echo "Processing webhook: ", webhookData
  
  await ctx.json(%*{
    "message": "Webhook received and processed",
    "eventType": if webhookData.hasKey("type"): webhookData["type"] else: %"unknown",
    "processedAt": $now()
  })
)

# ==================== BATCH OPERATIONS ====================

app.post("/api/batch/users", validateJSONMiddleware(), proc(ctx: Context): Future[void] {.async, closure.} =
  let batchData = ctx.jsonBody()
  
  if not batchData.hasKey("users") or batchData["users"].kind != JArray:
    discard ctx.status(Http400)
    await ctx.json(%*{"error": "Users array is required"})
    return
  
  let users = batchData["users"]
  var processed = 0
  var failed = 0
  
  for user in users:
    if user.hasKey("name") and user.hasKey("email"):
      processed += 1
    else:
      failed += 1
  
  await ctx.json(%*{
    "message": "Batch processing completed",
    "processed": processed,
    "failed": failed,
    "total": users.len,
    "processedAt": $now()
  })
)

# ==================== REAL-TIME NOTIFICATIONS ====================

app.get("/api/notifications", proc(ctx: Context): Future[void] {.async.} =
  let unreadOnly = ctx.getQuery("unread") == "true"
  let limit = ctx.getQuery("limit")
  
  await ctx.json(%*{
    "notifications": [
      {"id": 1, "message": "New user registered", "type": "info", "read": false, "createdAt": $now()},
      {"id": 2, "message": "System backup completed", "type": "success", "read": true, "createdAt": $now()},
      {"id": 3, "message": "High CPU usage detected", "type": "warning", "read": false, "createdAt": $now()}
    ],
    "filters": {
      "unreadOnly": unreadOnly,
      "limit": limit
    },
    "summary": {
      "total": 3,
      "unread": 2
    }
  })
)

# ==================== ERROR HANDLING EXAMPLES ====================

app.get("/api/error/500", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.status(Http500)
  await ctx.json(%*{
    "error": "Internal Server Error",
    "code": 500,
    "message": "Something went wrong on our end",
    "requestId": "req-" & $now().toTime().toUnix()
  })
)

app.get("/api/error/404", proc(ctx: Context): Future[void] {.async.} =
  discard ctx.status(Http404)
  await ctx.json(%*{
    "error": "Not Found",
    "code": 404,
    "message": "The requested resource was not found"
  })
)

# ==================== HEALTH CHECK WITH DETAILED INFO ====================

app.get("/api/health/detailed", proc(ctx: Context): Future[void] {.async.} =
  await ctx.json(%*{
    "status": "healthy",
    "timestamp": $now(),
    "version": "0.1.0",
    "environment": "development",
    "services": {
      "database": {"status": "connected", "responseTime": "5ms"},
      "cache": {"status": "connected", "responseTime": "1ms"},
      "queue": {"status": "running", "pendingJobs": 0}
    },
    "system": {
      "cpuUsage": "25%",
      "memoryUsage": "512MB",
      "diskSpace": "75% free"
    }
  })
)

# ==================== SERVER SETUP ====================

# Create directories if they don't exist
if not dirExists("public"):
  createDir("public")
if not dirExists("public/files"):
  createDir("public/files")

# Start server
waitFor app.listen(3000, proc() =
  echo "🚀 Rakta Framework Server running at http://localhost:3000"
  echo "📚 Available endpoints:"
  echo "   GET  /                     - Home page"
  echo "   GET  /health               - Basic health check"
  echo "   GET  /api/users            - Get all users (with pagination & search)"
  echo "   POST /api/users            - Create new user"
  echo "   GET  /api/users/:id        - Get user by ID"
  echo "   PUT  /api/users/:id        - Update user"
  echo "   DELETE /api/users/:id      - Delete user"
  echo "   GET  /api/dashboard        - Protected dashboard (requires auth)"
  echo "   GET  /api/admin/logs       - Protected admin logs (requires auth)"
  echo "   POST /api/upload           - File upload simulation"
  echo "   GET  /api/search           - Search with filtering"
  echo "   GET  /api/analytics        - Analytics data"
  echo "   POST /api/webhooks/payment - Webhook endpoint"
  echo "   POST /api/batch/users      - Batch user operations"
  echo "   GET  /api/notifications    - Get notifications"
  echo "   PATCH /api/notifications/:id - Mark notification as read"
  echo "   GET  /api/health/detailed  - Detailed health check"
  echo ""
  echo "🔐 For protected routes, use header: Authorization: Bearer valid-token-123"
  echo "📁 Static files served from 'public' directory"
)