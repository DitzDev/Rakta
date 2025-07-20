import os, times, tables, strutils, asyncdispatch, asynchttpserver, json, httpcore
import types

proc newHotReloadConfig*(
  watchDirs: seq[string] = @[], 
  excludePatterns: seq[string] = @["*.nim", "*.exe", "*.log", "node_modules", ".git"],
  port: int = 3001,
  verbose: bool = true
): HotReloadConfig =
  HotReloadConfig(
    enabled: when defined(release): false else: true,
    watchDirs: watchDirs,
    excludePatterns: excludePatterns,
    port: port,
    verbose: verbose
  )

proc logInfo(config: HotReloadConfig, message: string) =
  if config.verbose and config.enabled:
    echo "[HOT-RELOAD] ", message

proc logStart(config: HotReloadConfig) =
  if config.verbose and config.enabled:
    echo "[START] Watching for file changes..."
    echo "[INFO] Monitoring directories: ", config.watchDirs.join(", ")
    echo "[INFO] Server-Sent Events server on port: ", config.port

proc shouldIgnoreFile(config: HotReloadConfig, filePath: string): bool =
  # let fileName = extractFilename(filePath)
  let ext = splitFile(filePath).ext.toLowerAscii()
  
  if ext == ".nim":
    return true

  for pattern in config.excludePatterns:
    if pattern.startsWith("*."):
      let patternExt = pattern[1..^1].toLowerAscii()
      if ext == patternExt:
        return true
    elif pattern in filePath:
      return true
  
  return false

proc scanDirectory(config: HotReloadConfig, dirPath: string, fileMap: var Table[string, Time]) =
  if not dirExists(dirPath):
    config.logInfo("Directory not found: " & dirPath)
    return
    
  try:
    for kind, path in walkDir(dirPath):
      case kind:
      of pcFile:
        if not config.shouldIgnoreFile(path):
          let info = getFileInfo(path)
          fileMap[path] = info.lastWriteTime
      of pcDir:
        let dirName = extractFilename(path)
        if dirName notin config.excludePatterns:
          config.scanDirectory(path, fileMap)
      else:
        discard
  except OSError:
    config.logInfo("Error scanning directory: " & dirPath)

proc initializeFileMap(config: HotReloadConfig): Table[string, Time] =
  result = initTable[string, Time]()
  for dir in config.watchDirs:
    config.scanDirectory(dir, result)

proc detectChanges(watcher: FileWatcher) {.async.} =
  while watcher.config.enabled:
    let currentFileMap = watcher.config.initializeFileMap()
    var hasChanges = false
    
    for filePath, newTime in currentFileMap:
      if filePath in watcher.fileTimestamps:
        let oldTime = watcher.fileTimestamps[filePath]
        if newTime > oldTime:
          watcher.config.logInfo("File changed: " & filePath)
          watcher.changedFiles.add(filePath)
          watcher.fileTimestamps[filePath] = newTime
          hasChanges = true
      else:
        watcher.config.logInfo("New file detected: " & filePath)
        watcher.changedFiles.add(filePath)
        watcher.fileTimestamps[filePath] = newTime
        hasChanges = true

    watcher.fileTimestamps = currentFileMap
    
    if hasChanges:
      watcher.lastChangeTime = epochTime()
      if watcher.changedFiles.len > 10:
        watcher.changedFiles = watcher.changedFiles[watcher.changedFiles.len-10..^1]
    
    await sleepAsync(1000)  # Check every 1 second

proc handleSSERequest(watcher: FileWatcher, req: asynchttpserver.Request) {.async.} =
  let headers = newHttpHeaders([
    ("Content-Type", "text/event-stream"),
    ("Cache-Control", "no-cache"),
    ("Connection", "keep-alive"),
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Headers", "Cache-Control")
  ])

  var body = "data: {\"type\":\"connected\",\"timestamp\":" & $epochTime() & "}\n\n"
  await req.respond(Http200, body, headers)
  
  var lastSentTime = 0.0
  
  while true:
    await sleepAsync(1000)
    
    if watcher.lastChangeTime > lastSentTime and watcher.changedFiles.len > 0:
      # let message = %*{
      # "type": "reload",
      # "files": watcher.changedFiles,
      # "timestamp": watcher.lastChangeTime
      # }
      
      # let eventData = "data: " & $message & "\n\n"
      
      try:
        # In a real implementation, we'd need to keep the connection alive
        # For simplicity, we'll use the polling approach with the client
        watcher.config.logInfo("Broadcasting reload event")
        lastSentTime = watcher.lastChangeTime
      except:
        break

proc handleStatusRequest(watcher: FileWatcher, req: asynchttpserver.Request) {.async.} =
  let response = %*{
    "status": "watching",
    "enabled": watcher.config.enabled,
    "lastChange": watcher.lastChangeTime,
    "changedFiles": watcher.changedFiles,
    "watchDirs": watcher.config.watchDirs
  }
  
  let headers = newHttpHeaders([
    ("Content-Type", "application/json"),
    ("Access-Control-Allow-Origin", "*")
  ])
  
  await req.respond(Http200, $response, headers)

proc startServer(watcher: FileWatcher) {.async.} =
  let server = newAsyncHttpServer()
  
  proc requestHandler(req: asynchttpserver.Request) {.async.} =
    case req.url.path:
    of "/events":
      await watcher.handleSSERequest(req)
    of "/status":
      await watcher.handleStatusRequest(req)
    of "/poll":
      # Simple polling endpoint
      let lastCheck = if req.url.query.len > 0: 
        try: parseFloat(req.url.query.split("=")[1])
        except: 0.0
      else: 0.0
        
      if watcher.lastChangeTime > lastCheck:
        let response = %*{
          "changed": true,
          "timestamp": watcher.lastChangeTime,
          "files": watcher.changedFiles
        }
        let headers = newHttpHeaders([
          ("Content-Type", "application/json"),
          ("Access-Control-Allow-Origin", "*")
        ])
        await req.respond(Http200, $response, headers)
      else:
        let response = %*{"changed": false}
        let headers = newHttpHeaders([
          ("Content-Type", "application/json"),
          ("Access-Control-Allow-Origin", "*")
        ])
        await req.respond(Http200, $response, headers)
    else:
      await req.respond(Http404, "Hot Reload Server - Endpoints: /status, /poll")
  
  await server.serve(Port(watcher.config.port), requestHandler)

proc newFileWatcher*(config: HotReloadConfig): FileWatcher =
  result = FileWatcher(
    config: config,
    fileTimestamps: config.initializeFileMap(),
    lastChangeTime: 0.0,
    changedFiles: @[]
  )

proc start*(watcher: FileWatcher) {.async.} =
  if not watcher.config.enabled:
    return
    
  watcher.config.logStart()
  
  # Start server and file watcher concurrently
  asyncCheck watcher.startServer()
  asyncCheck watcher.detectChanges()

const HOT_RELOAD_CLIENT_SCRIPT* = """
<script>
(function() {
  if (typeof window.hotReloadEnabled !== 'undefined') return;
  window.hotReloadEnabled = true;
  
  let lastCheckTime = 0;
  let pollInterval;
  
  function startPolling() {
    console.log('[HOT-RELOAD] Starting file watcher');
    
    pollInterval = setInterval(async () => {
      try {
        const response = await fetch(`http://localhost:$PORT/poll?t=${lastCheckTime}`);
        const data = await response.json();
        
        if (data.changed) {
          console.log('[HOT-RELOAD] Files changed:', data.files);
          lastCheckTime = data.timestamp;
          
          // Try to reload specific resources first
          let needsFullReload = false;
          
          for (const file of data.files) {
            const extension = file.split('.').pop().toLowerCase();
            if (!reloadSpecificResource(extension, file)) {
              needsFullReload = true;
            }
          }
          
          if (needsFullReload) {
            console.log('[HOT-RELOAD] Full page reload');
            window.location.reload();
          }
        }
      } catch (error) {
        console.log('[HOT-RELOAD] Poll error:', error.message);
      }
    }, 1000); // Poll every second
  }
  
  function reloadSpecificResource(extension, filePath) {
    switch (extension) {
      case 'css':
        reloadCSS();
        console.log('[HOT-RELOAD] CSS reloaded');
        return true;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        reloadImages();
        console.log('[HOT-RELOAD] Images reloaded');
        return true;
      default:
        return false; // Need full reload for JS, HTML, etc.
    }
  }
  
  function reloadCSS() {
    const links = document.querySelectorAll('link[rel="stylesheet"]');
    links.forEach(link => {
      const url = new URL(link.href);
      url.searchParams.set('t', Date.now());
      link.href = url.toString();
    });
  }
  
  function reloadImages() {
    const images = document.querySelectorAll('img');
    images.forEach(img => {
      const url = new URL(img.src);
      url.searchParams.set('t', Date.now());
      img.src = url.toString();
    });
  }
  
  // Start polling when page loads
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startPolling);
  } else {
    startPolling();
  }
  
  // Cleanup on page unload
  window.addEventListener('beforeunload', () => {
    if (pollInterval) {
      clearInterval(pollInterval);
    }
  });
})();
</script>
"""