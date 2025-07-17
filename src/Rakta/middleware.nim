import strutils, re, tables
import types

proc extractParamNames(pattern: string): seq[string] =
  result = @[]
  let regex = re":([a-zA-Z_][a-zA-Z0-9_]*)"
  var matches: array[1, string]
  var start = 0
  while pattern.find(regex, matches, start) != -1:
    result.add(matches[0])
    start = pattern.find(regex, matches, start) + matches[0].len + 1

proc patternToRegex(pattern: string): Regex =
  var regexPattern = pattern
  regexPattern = regexPattern.replace("/", "\\/")
  regexPattern = regexPattern.replace(re":([a-zA-Z_][a-zA-Z0-9_]*)", "([^/]+)")
  regexPattern = "^" & regexPattern & ".*$"  # Allow paths that start with pattern
  
  return re(regexPattern)

proc matchPath(middleware: PathMiddleware, path: string): (bool, Table[string, string]) =
  # Handle exact paths
  if middleware.isExact:
    if path.startsWith(middleware.pattern):
      return (true, initTable[string, string]())
    else:
      return (false, initTable[string, string]())
  
  # Handle parametric paths
  if middleware.compiledRegex == nil:
    return (false, initTable[string, string]())
  
  var matches: array[10, string]
  let matched = path.match(middleware.compiledRegex, matches)
  
  if not matched:
    return (false, initTable[string, string]())
  
  var params = initTable[string, string]()
  for i, paramName in middleware.paramNames:
    if i < matches.len and matches[i] != "":
      params[paramName] = matches[i]
  
  return (true, params)

proc createPathMiddleware*(pattern: string, handler: Handler): PathMiddleware =
  let isExact = not pattern.contains(':')
  
  return PathMiddleware(
    pattern: pattern,
    handler: handler,
    paramNames: if isExact: @[] else: extractParamNames(pattern),
    compiledRegex: if isExact: nil else: patternToRegex(pattern),
    isExact: isExact
  )

proc getMatchingPathMiddlewares*(app: App, path: string): seq[Handler] =
  result = @[]
  for pathMiddleware in app.pathMiddlewares:
    let (matched, _) = matchPath(pathMiddleware, path)
    if matched:
      result.add(pathMiddleware.handler)