import asyncnet, asyncdispatch, tables
import random

type
  WebSocketOpcode* = enum
    wsOpcodeContinuation = 0x0
    wsOpcodeText = 0x1
    wsOpcodeBinary = 0x2
    wsOpcodeClose = 0x8
    wsOpcodePing = 0x9
    wsOpcodePong = 0xa

  WebSocketState* = enum
    wsConnecting
    wsOpen
    wsClosing
    wsClosed

  WebSocketCloseCode* = enum
    wsCloseNormal = 1000
    wsCloseGoingAway = 1001
    wsCloseProtocolError = 1002
    wsCloseUnsupportedData = 1003
    wsCloseNoStatusReceived = 1005
    wsCloseAbnormalClosure = 1006
    wsCloseInvalidFramePayloadData = 1007
    wsClosePolicyViolation = 1008
    wsCloseMessageTooBig = 1009
    wsCloseMandatoryExtension = 1010
    wsCloseInternalServerError = 1011
    wsCloseServiceRestart = 1012
    wsCloseTryAgainLater = 1013
    wsCloseTlsHandshake = 1015

  WebSocketFrame* = object
    fin*: bool
    rsv1*, rsv2*, rsv3*: bool
    opcode*: WebSocketOpcode
    masked*: bool
    payloadLength*: uint64
    maskingKey*: array[4, byte]
    payload*: seq[byte]

  CompressionOptions* = object
    chunkSize*: int
    memLevel*: int
    level*: int

  PerMessageDeflateConfig* = object
    zlibDeflateOptions*: CompressionOptions
    zlibInflateOptions*: CompressionOptions
    clientNoContextTakeover*: bool
    serverNoContextTakeover*: bool
    serverMaxWindowBits*: int
    concurrencyLimit*: int
    threshold*: int
    enabled*: bool

  WebSocketServerConfig* = object
    port*: int
    host*: string
    perMessageDeflate*: PerMessageDeflateConfig
    maxFrameSize*: int
    maxMessageSize*: int
    pingInterval*: int
    pongTimeout*: int

  WebSocketConnection* = ref object
    socket*: AsyncSocket
    state*: WebSocketState
    id*: string
    server*: WebSocketServer
    extensions*: seq[string]
    compressionEnabled*: bool
    lastPing*: float
    lastPong*: float
    closeCode*: WebSocketCloseCode
    closeReason*: string
    fragmentBuffer*: seq[byte]
    fragmentOpcode*: WebSocketOpcode

  WebSocketServer* = ref object
    socket*: AsyncSocket
    config*: WebSocketServerConfig
    connections*: Table[string, WebSocketConnection]
    connectionCount*: int
    onConnection*: proc(ws: WebSocketConnection) {.async.}
    onMessage*: proc(ws: WebSocketConnection, data: string) {.async.}
    onBinary*: proc(ws: WebSocketConnection, data: seq[byte]) {.async.}
    onClose*: proc(ws: WebSocketConnection, code: WebSocketCloseCode, reason: string) {.async.}
    onError*: proc(ws: WebSocketConnection, error: ref Exception) {.async.}
    running*: bool

  WebSocketError* = object of CatchableError

proc generateConnectionId*(): string =
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  result = newString(16)
  for i in 0..<16:
    result[i] = chars[rand(chars.len - 1)]

proc newPerMessageDeflateConfig*(): PerMessageDeflateConfig =
  result.zlibDeflateOptions = CompressionOptions(
    chunkSize: 1024,
    memLevel: 7,
    level: 3
  )
  result.zlibInflateOptions = CompressionOptions(
    chunkSize: 10 * 1024,
    memLevel: 8,
    level: 6
  )
  result.clientNoContextTakeover = true
  result.serverNoContextTakeover = true
  result.serverMaxWindowBits = 10
  result.concurrencyLimit = 10
  result.threshold = 1024
  result.enabled = true

proc newWebSocketServerConfig*(port: int = 8080): WebSocketServerConfig =
  result.port = port
  result.host = "0.0.0.0"
  result.perMessageDeflate = newPerMessageDeflateConfig()
  result.maxFrameSize = 1024 * 1024  # 1MB
  result.maxMessageSize = 10 * 1024 * 1024  # 10MB
  result.pingInterval = 30000  # 30 seconds
  result.pongTimeout = 5000   # 5 seconds