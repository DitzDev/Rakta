import RaktaWebsockets
import asyncdispatch, json, strutils, times

proc main() {.async.} =
  var deflateConfig = newPerMessageDeflateConfig()
  deflateConfig.zlibDeflateOptions.chunkSize = 1024
  deflateConfig.zlibDeflateOptions.memLevel = 7
  deflateConfig.zlibDeflateOptions.level = 3
  deflateConfig.zlibInflateOptions.chunkSize = 10 * 1024
  deflateConfig.clientNoContextTakeover = true
  deflateConfig.serverNoContextTakeover = true
  deflateConfig.serverMaxWindowBits = 10
  deflateConfig.concurrencyLimit = 10
  deflateConfig.threshold = 1024
  
  let server = newRaktaServer(
    port = 8080,
    host = "0.0.0.0",
    perMessageDeflate = deflateConfig
  )
  
  server.onConnection = proc(ws: WebSocketConnection) {.async.} =
    echo "✅ New WebSocket connection established"
    echo "   ID: ", ws.id
    echo "   Extensions: ", ws.extensions.join(", ")
    echo "   Compression: ", ws.compressionEnabled
    echo "   Total connections: ", server.getConnections().len
    
    let welcome = %*{
      "type": "welcome",
      "message": "Connected to Rakta WebSocket Server",
      "connectionId": ws.id,
      "timestamp": epochTime(),
      "features": {
        "compression": ws.compressionEnabled,
        "extensions": ws.extensions
      }
    }
    await ws.send($welcome)
  
  server.onMessage = proc(ws: WebSocketConnection, message: string) {.async.} =
    echo "📨 Received text message from ", ws.id, ": ", message
    
    try:
      let json = parseJson(message)
      
      case json{"type"}.getStr(""):
      of "echo":
        let response = %*{
          "type": "echo",
          "original": json,
          "timestamp": epochTime(),
          "connectionId": ws.id
        }
        await ws.send($response)
      
      of "broadcast":
        let broadcastMsg = %*{
          "type": "broadcast",
          "message": json{"message"}.getStr(""),
          "from": ws.id,
          "timestamp": epochTime()
        }
        await server.broadcast($broadcastMsg)
      
      of "ping":
        let pong = %*{
          "type": "pong",
          "timestamp": epochTime(),
          "connectionId": ws.id
        }
        await ws.send($pong)
      
      of "stats":
        let stats = %*{
          "type": "stats",
          "totalConnections": server.getConnections().len,
          "timestamp": epochTime(),
          "server": "Rakta WebSocket Framework"
        }
        await ws.send($stats)
      
      else:
        let echo = %*{
          "type": "echo",
          "original": message,
          "timestamp": epochTime(),
          "connectionId": ws.id
        }
        await ws.send($echo)
    
    except JsonParsingError:
      let response = %*{
        "type": "echo",
        "message": message,
        "timestamp": epochTime(),
        "connectionId": ws.id
      }
      await ws.send($response)
  
  server.onBinary = proc(ws: WebSocketConnection, data: seq[byte]) {.async.} =
    echo "📦 Received binary message from ", ws.id, " (", data.len, " bytes)"
    
    await ws.send(data)
  
  server.onClose = proc(ws: WebSocketConnection, code: WebSocketCloseCode, reason: string) {.async.} =
    echo "❌ WebSocket connection closed"
    echo "   ID: ", ws.id
    echo "   Code: ", code, " (", code.ord, ")"
    echo "   Reason: ", reason
    echo "   Remaining connections: ", server.getConnections().len
  
  server.onError = proc(ws: WebSocketConnection, error: ref Exception) {.async.} =
    echo "⚠️  WebSocket error on connection ", ws.id, ": ", error.msg
  
  proc statsLoop() {.async.} =
    while server.running:
      await sleepAsync(30000)  # 30 seconds
      if server.getConnections().len > 0:
        let stats = %*{
          "type": "server_stats",
          "timestamp": epochTime(),
          "totalConnections": server.getConnections().len,
          "uptime": epochTime(),  # Simple uptime
          "server": "Rakta WebSocket Framework v1.0.0"
        }
        await server.broadcast($stats)
  
  # Start stats loop
  asyncCheck statsLoop()
  
  echo "🚀 Starting Rakta WebSocket Server..."
  echo "   Port: 8080"
  echo "   Per-Message Deflate: Enabled"
  echo "   Press Ctrl+C to stop"
  
  # Handle shutdown gracefully
  proc handleShutdown() {.async.} =
    echo "\n🛑 Shutting down server..."
    await server.close()
    echo "✅ Server stopped gracefully"
  
  # Start server
  try:
    await server.listen()
  except Exception as e:
    echo "❌ Server error: ", e.msg
  finally:
    await handleShutdown()

when isMainModule:
  waitFor main()