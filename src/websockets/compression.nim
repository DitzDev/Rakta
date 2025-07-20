import zlib_wrapper, strutils
import types

type
  CompressionContext* = object
    deflateStream*: ZStream
    inflateStream*: ZStream
    initialized*: bool
    config*: PerMessageDeflateConfig

proc initCompressionContext*(config: PerMessageDeflateConfig): CompressionContext =
  result.config = config
  result.initialized = true
  
  # Initialize deflate stream
  result.deflateStream.zalloc = nil
  result.deflateStream.zfree = nil
  result.deflateStream.opaque = nil
  result.deflateStream.nextIn = nil
  result.deflateStream.availIn = 0
  result.deflateStream.nextOut = nil
  result.deflateStream.availOut = 0
  
  let deflateResult = deflateInit2(
    result.deflateStream,
    config.zlibDeflateOptions.level.cint,
    Z_DEFLATED.cint,
    (-config.serverMaxWindowBits).cint,  # Negative for raw deflate
    config.zlibDeflateOptions.memLevel.cint,
    Z_DEFAULT_STRATEGY.cint
  )
  
  if deflateResult != Z_OK:
    raise newException(WebSocketError, "Failed to initialize deflate: " & $deflateResult)
  
  # Initialize inflate stream
  result.inflateStream.zalloc = nil
  result.inflateStream.zfree = nil
  result.inflateStream.opaque = nil
  result.inflateStream.nextIn = nil
  result.inflateStream.availIn = 0
  result.inflateStream.nextOut = nil
  result.inflateStream.availOut = 0
  
  let inflateResult = inflateInit2(
    result.inflateStream,
    (-config.serverMaxWindowBits).cint  # Negative for raw inflate
  )
  
  if inflateResult != Z_OK:
    discard deflateEnd(result.deflateStream)
    raise newException(WebSocketError, "Failed to initialize inflate: " & $inflateResult)

proc destroyCompressionContext*(ctx: var CompressionContext) =
  if ctx.initialized:
    discard deflateEnd(ctx.deflateStream)
    discard inflateEnd(ctx.inflateStream)
    ctx.initialized = false

proc compressMessage*(ctx: var CompressionContext, data: seq[byte]): seq[byte] =
  if not ctx.initialized or data.len < ctx.config.threshold:
    return data
  
  var output = newSeq[byte](data.len + 32)  # Initial buffer size
  var outputSize = 0
  
  ctx.deflateStream.nextIn = cast[ptr uint8](unsafeAddr data[0])
  ctx.deflateStream.availIn = data.len.cuint
  
  while ctx.deflateStream.availIn > 0 or ctx.deflateStream.availOut == 0:
    if outputSize >= output.len:
      output.setLen(output.len * 2)
    
    ctx.deflateStream.nextOut = cast[ptr uint8](addr output[outputSize])
    ctx.deflateStream.availOut = (output.len - outputSize).cuint
    
    let deflateResult = deflate(ctx.deflateStream, Z_SYNC_FLUSH.cint)
    
    if deflateResult != Z_OK and deflateResult != Z_BUF_ERROR:
      raise newException(WebSocketError, "Deflate failed: " & $deflateResult)
    
    outputSize = output.len - ctx.deflateStream.availOut.int
  
  # Remove the trailing 0x00 0x00 0xFF 0xFF from SYNC_FLUSH
  if outputSize >= 4:
    let suffix = output[outputSize-4..outputSize-1]
    if suffix == @[0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8]:
      outputSize -= 4
  
  output.setLen(outputSize)
  
  # Reset context if no context takeover
  if ctx.config.serverNoContextTakeover:
    discard deflateEnd(ctx.deflateStream)
    ctx.deflateStream.zalloc = nil
    ctx.deflateStream.zfree = nil
    ctx.deflateStream.opaque = nil
    ctx.deflateStream.nextIn = nil
    ctx.deflateStream.availIn = 0
    ctx.deflateStream.nextOut = nil
    ctx.deflateStream.availOut = 0
    
    let deflateResult = deflateInit2(
      ctx.deflateStream,
      ctx.config.zlibDeflateOptions.level.cint,
      Z_DEFLATED.cint,
      (-ctx.config.serverMaxWindowBits).cint,
      ctx.config.zlibDeflateOptions.memLevel.cint,
      Z_DEFAULT_STRATEGY.cint
    )
    if deflateResult != Z_OK:
      raise newException(WebSocketError, "Failed to reset deflate context")
  
  return output

proc decompressMessage*(ctx: var CompressionContext, data: seq[byte]): seq[byte] =
  if not ctx.initialized or data.len == 0:
    return data
  
  # Add the 0x00 0x00 0xFF 0xFF suffix required for inflate
  var inputData = data & @[0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8]
  
  var output = newSeq[byte](data.len * 4)  # Initial buffer size
  var outputSize = 0
  
  ctx.inflateStream.nextIn = cast[ptr uint8](unsafeAddr inputData[0])
  ctx.inflateStream.availIn = inputData.len.cuint
  
  while ctx.inflateStream.availIn > 0 or ctx.inflateStream.availOut == 0:
    if outputSize >= output.len:
      output.setLen(output.len * 2)
    
    ctx.inflateStream.nextOut = cast[ptr uint8](addr output[outputSize])
    ctx.inflateStream.availOut = (output.len - outputSize).cuint
    
    let inflateResult = inflate(ctx.inflateStream, Z_SYNC_FLUSH.cint)
    
    if inflateResult != Z_OK and inflateResult != Z_BUF_ERROR:
      if inflateResult == Z_STREAM_END:
        break
      else:
        raise newException(WebSocketError, "Inflate failed: " & $inflateResult)
    
    outputSize = output.len - ctx.inflateStream.availOut.int
    
    if inflateResult == Z_STREAM_END:
      break
  
  output.setLen(outputSize)
  
  # Reset context if no context takeover
  if ctx.config.clientNoContextTakeover:
    discard inflateEnd(ctx.inflateStream)
    ctx.inflateStream.zalloc = nil
    ctx.inflateStream.zfree = nil
    ctx.inflateStream.opaque = nil
    ctx.inflateStream.nextIn = nil
    ctx.inflateStream.availIn = 0
    ctx.inflateStream.nextOut = nil
    ctx.inflateStream.availOut = 0
    
    let inflateResult = inflateInit2(
      ctx.inflateStream,
      (-ctx.config.serverMaxWindowBits).cint
    )
    if inflateResult != Z_OK:
      raise newException(WebSocketError, "Failed to reset inflate context")
  
  return output

proc parsePerMessageDeflateExtension*(extensionHeader: string): PerMessageDeflateConfig =
  result = newPerMessageDeflateConfig()
  result.enabled = true
  
  let parts = extensionHeader.split(";")
  for part in parts:
    let param = part.strip()
    if param.startsWith("server_max_window_bits="):
      let value = param.split("=")[1].strip()
      try:
        result.serverMaxWindowBits = value.parseInt()
      except:
        discard
    elif param == "server_no_context_takeover":
      result.serverNoContextTakeover = true
    elif param == "client_no_context_takeover":
      result.clientNoContextTakeover = true

proc formatPerMessageDeflateExtension*(config: PerMessageDeflateConfig): string =
  result = "permessage-deflate"
  
  if config.serverNoContextTakeover:
    result &= "; server_no_context_takeover"
  
  if config.clientNoContextTakeover:
    result &= "; client_no_context_takeover"
  
  if config.serverMaxWindowBits != 15:
    result &= "; server_max_window_bits=" & $config.serverMaxWindowBits