import asyncdispatch, os, strutils, tables, httpcore
import types, context, response, router

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

proc serveStatic*(staticDir: string, urlPrefix: string = ""): Handler =
  return proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.req.httpMethod != HttpGet:
      await ctx.next()
      return
    
    var requestPath = ctx.req.path
    
    let (existingRoute, _) = ctx.app.findRoute(ctx.req.httpMethod, requestPath)
    if existingRoute != nil:
      await ctx.next()
      return
    
    if urlPrefix.len > 0:
      if not requestPath.startsWith(urlPrefix):
        await ctx.next()
        return
 
      requestPath = requestPath[urlPrefix.len..^1]
    
    if not requestPath.startsWith("/"):
      requestPath = "/" & requestPath
    
    if requestPath.startsWith("/"):
      requestPath = requestPath[1..^1]

    if requestPath.len == 0:
      # We need a fallback?
      requestPath = "index.html"
    
    let filePath = staticDir / requestPath
    
    if not fileExists(filePath):
      await ctx.next()
      return
    
    try:
      let normalizedStaticDir = staticDir.expandFilename()
      let normalizedFilePath = filePath.expandFilename()
      
      if not normalizedFilePath.startsWith(normalizedStaticDir):
        await ctx.next()
        return
    except:
      # Fallback to next if errors happens
      await ctx.next()
      return
    
    try:
      let content = readFile(filePath)
      let ext = splitFile(filePath).ext
      let mimeType = getMimeType(ext)
      
      discard ctx.setHeader("Content-Type", mimeType)
      discard ctx.setHeader("Content-Length", $content.len)

      discard ctx.setHeader("Cache-Control", "public, max-age=3600")
      
      await ctx.send(content)
    except Exception as e:
      echo "Error serving static file: ", e.msg
      await ctx.next()

# Overload untuk backward compatibility
proc serveStatic*(staticDir: string): Handler =
  return serveStatic(staticDir, "")