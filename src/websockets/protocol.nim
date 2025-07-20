import strutils, base64, endians, tables, random
import checksums/sha1
import types

const
  WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  WS_VERSION = "13"

proc parseHttpRequest*(request: string): Table[string, string] =
  result = initTable[string, string]()
  let lines = request.split("\r\n")
  
  if lines.len > 0:
    let requestLine = lines[0].split(" ")
    if requestLine.len >= 3:
      result["method"] = requestLine[0]
      result["path"] = requestLine[1]
      result["version"] = requestLine[2]
  
  for i in 1..<lines.len:
    let line = lines[i]
    if ":" in line:
      let parts = line.split(":", 1)
      if parts.len == 2:
        result[parts[0].strip().toLowerAscii()] = parts[1].strip()

proc generateWebSocketAccept*(key: string): string =
  let combined = key & WS_MAGIC_STRING
  let hash = sha1.secureHash(combined)
  result = base64.encode($hash)

proc createWebSocketHandshakeResponse*(key: string, extensions: seq[string] = @[]): string =
  result = "HTTP/1.1 101 Switching Protocols\r\n"
  result &= "Upgrade: websocket\r\n"
  result &= "Connection: Upgrade\r\n"
  result &= "Sec-WebSocket-Accept: " & generateWebSocketAccept(key) & "\r\n"
  
  if extensions.len > 0:
    result &= "Sec-WebSocket-Extensions: " & extensions.join("; ") & "\r\n"
  
  result &= "\r\n"

proc validateWebSocketHandshake*(headers: Table[string, string]): bool =
  result = headers.hasKey("upgrade") and
           headers.hasKey("connection") and
           headers.hasKey("sec-websocket-key") and
           headers.hasKey("sec-websocket-version") and
           headers["upgrade"].toLowerAscii() == "websocket" and
           "upgrade" in headers["connection"].toLowerAscii() and
           headers["sec-websocket-version"] == WS_VERSION

# Helper function to safely convert byte to WebSocketOpcode
proc toWebSocketOpcode(value: byte): WebSocketOpcode =
  case value and 0x0F:
  of 0x0: wsOpcodeContinuation
  of 0x1: wsOpcodeText
  of 0x2: wsOpcodeBinary
  of 0x8: wsOpcodeClose
  of 0x9: wsOpcodePing
  of 0xA: wsOpcodePong
  else:
    raise newException(WebSocketError, "Invalid WebSocket opcode: " & $(value and 0x0F))

proc parseWebSocketFrame*(data: seq[byte]): WebSocketFrame =
  if data.len < 2:
    raise newException(WebSocketError, "Frame too short")
  
  result.fin = (data[0] and 0x80) != 0
  result.rsv1 = (data[0] and 0x40) != 0
  result.rsv2 = (data[0] and 0x20) != 0
  result.rsv3 = (data[0] and 0x10) != 0
  result.opcode = toWebSocketOpcode(data[0])
  
  result.masked = (data[1] and 0x80) != 0
  let payloadLen = data[1] and 0x7F
  
  var headerSize = 2
  
  if payloadLen == 126:
    if data.len < 4:
      raise newException(WebSocketError, "Frame too short for extended length")
    var len16: uint16
    bigEndian16(addr len16, unsafeAddr data[2])
    result.payloadLength = len16.uint64
    headerSize = 4
  elif payloadLen == 127:
    if data.len < 10:
      raise newException(WebSocketError, "Frame too short for extended length")
    var len64: uint64
    bigEndian64(addr len64, unsafeAddr data[2])
    result.payloadLength = len64
    headerSize = 10
  else:
    result.payloadLength = payloadLen.uint64
  
  if result.masked:
    if data.len < headerSize + 4:
      raise newException(WebSocketError, "Frame too short for masking key")
    result.maskingKey = [data[headerSize], data[headerSize + 1], 
                        data[headerSize + 2], data[headerSize + 3]]
    headerSize += 4
  
  if data.len < headerSize + result.payloadLength.int:
    raise newException(WebSocketError, "Frame too short for payload")
  
  result.payload = newSeq[byte](result.payloadLength.int)
  for i in 0..<result.payloadLength.int:
    result.payload[i] = data[headerSize + i]
    if result.masked:
      result.payload[i] = result.payload[i] xor result.maskingKey[i mod 4]

proc createWebSocketFrame*(opcode: WebSocketOpcode, payload: seq[byte], masked: bool = false): seq[byte] =
  result = newSeq[byte]()

  result.add(0x80 or opcode.byte)
  
  let payloadLen = payload.len.uint64
  
  if payloadLen < 126:
    result.add((if masked: 0x80 else: 0x00) or payloadLen.byte)
  elif payloadLen < 65536:
    result.add(((if masked: 0x80 else: 0x00) or 126).byte)
    var len16 = payloadLen.uint16
    var bytes: array[2, byte]
    bigEndian16(addr bytes[0], addr len16)
    result.add(bytes[0])
    result.add(bytes[1])
  else:
    result.add(((if masked: 0x80 else: 0x00) or 127).byte)
    var bytes: array[8, byte]
    bigEndian64(addr bytes[0], unsafeAddr payloadLen)
    for b in bytes:
      result.add(b)

  var maskingKey: array[4, byte]
  if masked:
    for i in 0..<4:
      maskingKey[i] = rand(256).byte
      result.add(maskingKey[i])

  for i, b in payload:
    if masked:
      result.add(b xor maskingKey[i mod 4])
    else:
      result.add(b)

proc createTextFrame*(text: string, masked: bool = false): seq[byte] =
  createWebSocketFrame(wsOpcodeText, cast[seq[byte]](@text), masked)

proc createBinaryFrame*(data: seq[byte], masked: bool = false): seq[byte] =
  createWebSocketFrame(wsOpcodeBinary, data, masked)

proc createCloseFrame*(code: WebSocketCloseCode, reason: string = "", masked: bool = false): seq[byte] =
  var payload = newSeq[byte](2 + reason.len)
  let codeBytes = code.uint16
  bigEndian16(addr payload[0], unsafeAddr codeBytes)
  for i, c in reason:
    payload[2 + i] = c.byte
  createWebSocketFrame(wsOpcodeClose, payload, masked)

proc createPingFrame*(data: seq[byte] = @[], masked: bool = false): seq[byte] =
  createWebSocketFrame(wsOpcodePing, data, masked)

proc createPongFrame*(data: seq[byte] = @[], masked: bool = false): seq[byte] =
  createWebSocketFrame(wsOpcodePong, data, masked)