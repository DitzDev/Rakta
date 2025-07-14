import asyncdispatch, os, strutils, tables, httpcore
import types, context, response

const mimeType = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".txt": "text/plain",
  ".pdf": "application/pdf"
}.toTable()

proc getMimeType(ext: string): string =
  let lowerExt = ext.toLowerAscii()
  if mimeType.hasKey(lowerExt):
    return mimeType[lowerExt]
  return "application/octet-stream"

proc serveStatic*(staticDir: string): Handler =
  return proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.req.httpMethod != HttpGet:
      await ctx.next()
      return
    
    let requestPath = ctx.req.path
    let filePath = staticDir / requestPath
    
    if not fileExists(filePath):
      await ctx.next()
      return
    
    try:
      let content = readFile(filePath)
      let ext = splitFile(filePath).ext
      let mimeType = getMimeType(ext)
      
      discard ctx.setHeader("Content-Type", mimeType)
      await ctx.send(content)
    except:
      await ctx.next()