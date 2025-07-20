import asyncnet, asyncdispatch, net, strutils, tables
import types, protocol, connection, compression

proc newWebSocketServer*(config: WebSocketServerConfig): WebSocketServer =
  result = WebSocketServer(
    socket: newAsyncSocket(),
    config: config,
    connections: initTable[string, WebSocketConnection](),
    connectionCount: 0,
    running: false
  )

proc onConnection*(server: WebSocketServer, callback: proc(ws: WebSocketConnection) {.async.}) =
  server.onConnection = callback

proc onMessage*(server: WebSocketServer, callback: proc(ws: WebSocketConnection, data: string) {.async.}) =
  server.onMessage = callback

proc onBinary*(server: WebSocketServer, callback: proc(ws: WebSocketConnection, data: seq[byte]) {.async.}) =
  server.onBinary = callback

proc onClose*(server: WebSocketServer, callback: proc(ws: WebSocketConnection, code: WebSocketCloseCode, reason: string) {.async.}) =
  server.onClose = callback

proc onError*(server: WebSocketServer, callback: proc(ws: WebSocketConnection, error: ref Exception) {.async.}) =
  server.onError = callback

proc broadcast*(server: WebSocketServer, message: string) {.async.} =
  var tasks: seq[Future[void]]
  for ws in server.connections.values:
    if ws.isConnected:
      tasks.add(ws.send(message))
  
  if tasks.len > 0:
    await all(tasks)

proc broadcast*(server: WebSocketServer, data: seq[byte]) {.async.} =
  var tasks: seq[Future[void]]
  for ws in server.connections.values:
    if ws.isConnected:
      tasks.add(ws.send(data))
  
  if tasks.len > 0:
    await all(tasks)

proc getConnections*(server: WebSocketServer): seq[WebSocketConnection] =
  result = @[]
  for ws in server.connections.values:
    if ws.isConnected:
      result.add(ws)

proc handleHttpUpgrade*(server: WebSocketServer, client: AsyncSocket) {.async.} =
  try:
    # Set socket options for better performance
    client.setSockOpt(OptNoDelay, true)
    client.setSockOpt(OptKeepAlive, true)
    
    # Read HTTP request
    var requestData = ""
    
    while true:
      # Fix: AsyncSocket.recv() only accepts size parameter and returns Future[string]
      let buffer = await client.recv(4096)
      if buffer.len == 0:
        client.close()
        return
      
      requestData.add(buffer)
      
      # Check if we have complete headers
      if "\r\n\r\n" in requestData:
        break
      
      # Prevent excessive header size
      if requestData.len > 8192:
        client.close()
        return
    
    # Parse HTTP headers
    let headers = parseHttpRequest(requestData)
    
    # Validate WebSocket handshake
    if not validateWebSocketHandshake(headers):
      let response = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
      await client.send(response)
      client.close()
      return
    
    # Check for extensions
    var extensions: seq[string] = @[]
    var compressionConfig = server.config.perMessageDeflate
    
    if headers.hasKey("sec-websocket-extensions") and compressionConfig.enabled:
      let extensionHeader = headers["sec-websocket-extensions"]
      if "permessage-deflate" in extensionHeader:
        compressionConfig = parsePerMessageDeflateExtension(extensionHeader)
        compressionConfig.enabled = true
        extensions.add(formatPerMessageDeflateExtension(compressionConfig))
    
    # Create WebSocket connection
    let ws = newWebSocketConnection(client, server)
    ws.extensions = extensions
    ws.compressionEnabled = compressionConfig.enabled
    
    # Send handshake response
    let wsKey = headers["sec-websocket-key"]
    let response = createWebSocketHandshakeResponse(wsKey, extensions)
    await client.send(response)
    
    # Handle the WebSocket connection
    await ws.handleConnection()
    
  except Exception as e:
    try:
      client.close()
    except:
      discard
    
    if server.onError != nil:
      let dummyWs = WebSocketConnection(socket: client, server: server)
      await server.onError(dummyWs, cast[ref Exception](e))

proc listen*(server: WebSocketServer) {.async.} =
  if server.running:
    return
  
  server.running = true
  
  try:
    server.socket.setSockOpt(OptReuseAddr, true)
    server.socket.bindAddr(Port(server.config.port), server.config.host)
    server.socket.listen()
    
    echo "Rakta WebSocket server listening on ", server.config.host, ":", server.config.port
    
    while server.running:
      try:
        let client = await server.socket.accept()
        asyncCheck server.handleHttpUpgrade(client)
      except Exception as e:
        if server.running:
          echo "Error accepting connection: ", e.msg
          continue
        else:
          break
  
  except Exception as e:
    echo "Server error: ", e.msg
    server.running = false
    raise

proc close*(server: WebSocketServer) {.async.} =
  if not server.running:
    return
  
  server.running = false
  
  # Close all connections
  var closeTasks: seq[Future[void]] = @[]
  for ws in server.connections.values:
    closeTasks.add(ws.close(wsCloseGoingAway, "Server shutting down"))
  
  if closeTasks.len > 0:
    await all(closeTasks)
  
  # Close server socket
  server.socket.close()
  server.connections.clear()
  server.connectionCount = 0
  
  echo "Rakta WebSocket server closed"

# Convenience constructor
proc newRaktaServer*(port: int = 8080, 
                     host: string = "0.0.0.0",
                     perMessageDeflate: PerMessageDeflateConfig = newPerMessageDeflateConfig()): WebSocketServer =
  let config = WebSocketServerConfig(
    port: port,
    host: host,
    perMessageDeflate: perMessageDeflate,
    maxFrameSize: 1024 * 1024,
    maxMessageSize: 10 * 1024 * 1024,
    pingInterval: 30000,
    pongTimeout: 5000
  )
  result = newWebSocketServer(config)