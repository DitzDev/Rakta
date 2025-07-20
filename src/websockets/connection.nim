import asyncnet, asyncdispatch, times, strutils, tables
import types, protocol, compression

type
  ConnectionContext* = object
    compressionContext*: CompressionContext
    fragmentBuffer*: seq[byte]
    fragmentOpcode*: WebSocketOpcode
    lastActivity*: float

proc close*(ws: WebSocketConnection, code: WebSocketCloseCode = wsCloseNormal, reason: string = "") {.async.}

proc newWebSocketConnection*(socket: AsyncSocket, server: WebSocketServer): WebSocketConnection =
  result = WebSocketConnection(
    socket: socket,
    state: wsConnecting,
    id: generateConnectionId(),
    server: server,
    extensions: @[],
    compressionEnabled: false,
    lastPing: 0.0,
    lastPong: epochTime(),
    closeCode: wsCloseNormal,
    closeReason: "",
    fragmentBuffer: @[],
    fragmentOpcode: wsOpcodeContinuation
  )

proc isConnected*(ws: WebSocketConnection): bool =
  ws.state == wsOpen and not ws.socket.isClosed

proc handlePing*(ws: WebSocketConnection, payload: seq[byte]) {.async.} =
  if ws.isConnected:
    let pongFrame = createPongFrame(payload)
    try:
      let frameStr = cast[string](pongFrame)
      await ws.socket.send(frameStr)
      ws.lastPong = epochTime()
    except:
      await ws.close(wsCloseAbnormalClosure, "Failed to send pong")

proc handlePong*(ws: WebSocketConnection, payload: seq[byte]) {.async.} =
  ws.lastPong = epochTime()

proc sendPing*(ws: WebSocketConnection, payload: seq[byte] = @[]) {.async.} =
  if ws.isConnected:
    let pingFrame = createPingFrame(payload)
    try:
      let frameStr = cast[string](pingFrame)
      await ws.socket.send(frameStr)
      ws.lastPing = epochTime()
    except:
      await ws.close(wsCloseAbnormalClosure, "Failed to send ping")

proc send*(ws: WebSocketConnection, message: string) {.async.} =
  if not ws.isConnected:
    return
  
  try:
    let frame = createTextFrame(message)
    let frameStr = cast[string](frame)
    await ws.socket.send(frameStr)
  except:
    await ws.close(wsCloseAbnormalClosure, "Failed to send message")

proc send*(ws: WebSocketConnection, data: seq[byte]) {.async.} =
  if not ws.isConnected:
    return
  
  try:
    let frame = createBinaryFrame(data)
    let frameStr = cast[string](frame)
    await ws.socket.send(frameStr)
  except:
    await ws.close(wsCloseAbnormalClosure, "Failed to send binary data")

proc close*(ws: WebSocketConnection, code: WebSocketCloseCode = wsCloseNormal, reason: string = "") {.async.} =
  if ws.state == wsClosed:
    return
  
  ws.state = wsClosing
  ws.closeCode = code
  ws.closeReason = reason
  
  try:
    if not ws.socket.isClosed:
      let closeFrame = createCloseFrame(code, reason)
      let frameStr = cast[string](closeFrame)
      await ws.socket.send(frameStr)
  except:
    discard  # Ignore send errors during close
  
  ws.state = wsClosed
  ws.socket.close()

  if ws.server != nil and ws.server.connections.hasKey(ws.id):
    ws.server.connections.del(ws.id)
    dec ws.server.connectionCount
  
  if ws.server != nil and ws.server.onClose != nil:
    try:
      await ws.server.onClose(ws, code, reason)
    except:
      discard

proc readFrame*(ws: WebSocketConnection): Future[WebSocketFrame] {.async.} =
  let headerData = await ws.socket.recv(2)
  if headerData.len != 2:
    raise newException(WebSocketError, "Connection closed by peer")
  
  let headerBuf = cast[seq[byte]](headerData)

  let fin = (headerBuf[0] and 0x80) != 0
  let opcodeValue = headerBuf[0] and 0x0F
  let opcode = case opcodeValue:
    of 0: wsOpcodeContinuation
    of 1: wsOpcodeText  
    of 2: wsOpcodeBinary
    of 8: wsOpcodeClose
    of 9: wsOpcodePing
    of 10: wsOpcodePong
    else: 
      raise newException(WebSocketError, "Invalid opcode: " & $opcodeValue)
  let masked = (headerBuf[1] and 0x80) != 0
  let payloadLen = headerBuf[1] and 0x7F
  
  var actualPayloadLen: uint64
  var totalHeaderSize = 2
  if payloadLen == 126:
    let extLenData = await ws.socket.recv(2)
    if extLenData.len != 2:
      raise newException(WebSocketError, "Connection closed reading extended length")
    let extLenBuf = cast[seq[byte]](extLenData)
    actualPayloadLen = (extLenBuf[0].uint64 shl 8) or extLenBuf[1].uint64
    totalHeaderSize += 2
  elif payloadLen == 127:
    let extLenData = await ws.socket.recv(8)
    if extLenData.len != 8:
      raise newException(WebSocketError, "Connection closed reading extended length")
    let extLenBuf = cast[seq[byte]](extLenData)
    actualPayloadLen = 0
    for i in 0..<8:
      actualPayloadLen = (actualPayloadLen shl 8) or extLenBuf[i].uint64
    totalHeaderSize += 8
  else:
    actualPayloadLen = payloadLen.uint64
  if actualPayloadLen.int > ws.server.config.maxFrameSize:
    raise newException(WebSocketError, "Frame too large")
  
  var maskingKey: array[4, byte]
  if masked:
    let maskData = await ws.socket.recv(4)
    if maskData.len != 4:
      raise newException(WebSocketError, "Connection closed reading mask")
    let maskBuf = cast[seq[byte]](maskData)
    for i in 0..<4:
      maskingKey[i] = maskBuf[i]
    totalHeaderSize += 4

  var payload = newSeq[byte](actualPayloadLen.int)
  if actualPayloadLen > 0:
    let payloadData = await ws.socket.recv(actualPayloadLen.int)
    if payloadData.len != actualPayloadLen.int:
      raise newException(WebSocketError, "Connection closed reading payload")
    let payloadBuf = cast[seq[byte]](payloadData)
    payload = payloadBuf
    
    if masked:
      for i in 0..<payload.len:
        payload[i] = payload[i] xor maskingKey[i mod 4]
  
  result = WebSocketFrame(
    fin: fin,
    opcode: opcode,
    masked: masked,
    payloadLength: actualPayloadLen,
    maskingKey: maskingKey,
    payload: payload
  )

proc processFrame*(ws: WebSocketConnection, frame: WebSocketFrame) {.async.} =
  case frame.opcode:
  of wsOpcodeText, wsOpcodeBinary:
    if frame.fin:
      var fullPayload: seq[byte]
      if ws.fragmentBuffer.len > 0:
        fullPayload = ws.fragmentBuffer & frame.payload
        ws.fragmentBuffer = @[]
        ws.fragmentOpcode = wsOpcodeContinuation
      else:
        fullPayload = frame.payload

      if fullPayload.len > ws.server.config.maxMessageSize:
        await ws.close(wsCloseMessageTooBig, "Message too large")
        return
      
      let messageOpcode = if ws.fragmentOpcode != wsOpcodeContinuation: 
                           ws.fragmentOpcode else: frame.opcode
      
      try:
        if messageOpcode == wsOpcodeText:
          if ws.server.onMessage != nil:
            var message = newString(fullPayload.len)
            for i in 0..<fullPayload.len:
              message[i] = char(fullPayload[i])
            await ws.server.onMessage(ws, message)
        elif messageOpcode == wsOpcodeBinary:
          if ws.server.onBinary != nil:
            await ws.server.onBinary(ws, fullPayload)
      except Exception as e:
        if ws.server.onError != nil:
          await ws.server.onError(ws, e)
    else:
      if ws.fragmentBuffer.len == 0:
        ws.fragmentOpcode = frame.opcode
      ws.fragmentBuffer &= frame.payload

      if ws.fragmentBuffer.len > ws.server.config.maxMessageSize:
        await ws.close(wsCloseMessageTooBig, "Fragmented message too large")
        return

  of wsOpcodeContinuation:
    if ws.fragmentBuffer.len == 0:
      await ws.close(wsCloseProtocolError, "Unexpected continuation frame")
      return
    
    ws.fragmentBuffer &= frame.payload
    
    if frame.fin:
      let fullPayload = ws.fragmentBuffer
      let messageOpcode = ws.fragmentOpcode
      ws.fragmentBuffer = @[]
      ws.fragmentOpcode = wsOpcodeContinuation
      
      if fullPayload.len > ws.server.config.maxMessageSize:
        await ws.close(wsCloseMessageTooBig, "Message too large")
        return
      
      try:
        if messageOpcode == wsOpcodeText:
          if ws.server.onMessage != nil:
            var message = newString(fullPayload.len)
            for i in 0..<fullPayload.len:
              message[i] = char(fullPayload[i])
            await ws.server.onMessage(ws, message)
        elif messageOpcode == wsOpcodeBinary:
          if ws.server.onBinary != nil:
            await ws.server.onBinary(ws, fullPayload)
      except Exception as e:
        if ws.server.onError != nil:
          await ws.server.onError(ws, e)
    else:
      if ws.fragmentBuffer.len > ws.server.config.maxMessageSize:
        await ws.close(wsCloseMessageTooBig, "Fragmented message too large")
        return

  of wsOpcodeClose:
    var code = wsCloseNormal
    var reason = ""
    
    if frame.payload.len >= 2:
      let codeValue = (frame.payload[0].uint16 shl 8) or frame.payload[1].uint16
      code = case codeValue:
        of 1000: wsCloseNormal
        of 1001: wsCloseGoingAway  
        of 1002: wsCloseProtocolError
        of 1003: wsCloseUnsupportedData
        of 1007: wsCloseInvalidFramePayloadData
        of 1008: wsClosePolicyViolation
        of 1009: wsCloseMessageTooBig
        of 1010: wsCloseMandatoryExtension
        of 1011: wsCloseInternalServerError
        of 1012: wsCloseServiceRestart
        of 1013: wsCloseTryAgainLater
        of 1015: wsCloseTLSHandshake
        else: wsCloseAbnormalClosure  # Default for unknown codes
      
      if frame.payload.len > 2:  
        var reason = newString(frame.payload.len - 2)
        for i in 0..<(frame.payload.len - 2):
          reason[i] = char(frame.payload[i + 2])
      else:
        reason = ""
    
    await ws.close(code, reason)

  of wsOpcodePing:
    await ws.handlePing(frame.payload)

  of wsOpcodePong:
    await ws.handlePong(frame.payload)

proc handleConnection*(ws: WebSocketConnection) {.async.} =
  ws.state = wsOpen
  
  ws.server.connections[ws.id] = ws
  inc ws.server.connectionCount

  if ws.server.onConnection != nil:
    try:
      await ws.server.onConnection(ws)
    except Exception as e:
      if ws.server.onError != nil:
        await ws.server.onError(ws, e)
  
  proc pingLoop() {.async.} =
    while ws.isConnected:
      await sleepAsync(ws.server.config.pingInterval)
      if ws.isConnected:
        let now = epochTime()
        
        if now - ws.lastPong > (ws.server.config.pongTimeout.float / 1000.0):
          await ws.close(wsCloseAbnormalClosure, "Pong timeout")
          break
        
        await ws.sendPing()

  asyncCheck pingLoop()
 
  try:
    while ws.isConnected:
      let frame = await ws.readFrame()
      await ws.processFrame(frame)
  except Exception as e:
    if ws.isConnected:
      if ws.server.onError != nil:
        await ws.server.onError(ws, e)
      await ws.close(wsCloseAbnormalClosure, "Connection error: " & e.msg)