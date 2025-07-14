import httpcore, tables, strutils, re, hashes
import types

var regexCache = initTable[string, Regex]()

proc extractParamNames(pattern: string): seq[string] =
  result = @[]
  let regex = re":([a-zA-Z_][a-zA-Z0-9_]*)"
  var matches: array[1, string]
  var start = 0
  while pattern.find(regex, matches, start) != -1:
    result.add(matches[0])
    start = pattern.find(regex, matches, start) + matches[0].len + 1

proc patternToRegex(pattern: string): Regex =
  # Cache regex compilation
  if regexCache.hasKey(pattern):
    return regexCache[pattern]
  
  var regexPattern = pattern
  regexPattern = regexPattern.replace("/", "\\/")
  regexPattern = regexPattern.replace(re":([a-zA-Z_][a-zA-Z0-9_]*)", "([^/]+)")
  regexPattern = "^" & regexPattern & "$"
  
  let compiledRegex = re(regexPattern)
  regexCache[pattern] = compiledRegex
  return compiledRegex

proc matchRoute(route: Route, path: string): (bool, Table[string, string]) =
  # Handle exact routes (static routes)
  if route.isExact:
    if route.pattern == path:
      return (true, initTable[string, string]())
    else:
      return (false, initTable[string, string]())
  
  # Handle parametric routes
  if route.compiledRegex == nil:
    return (false, initTable[string, string]())
  
  var matches: array[10, string]
  let matched = path.match(route.compiledRegex, matches)
  
  if not matched:
    return (false, initTable[string, string]())
  
  var params = initTable[string, string]()
  for i, paramName in route.paramNames:
    if i < matches.len and matches[i] != "":
      params[paramName] = matches[i]
  
  return (true, params)

proc addRoute*(app: App, httpMethod: HttpMethod, pattern: string, handler: Handler) =
  let isExact = not pattern.contains(':')
  
  let route = Route(
    httpMethod: httpMethod,
    pattern: pattern,
    handler: handler,
    paramNames: if isExact: @[] else: extractParamNames(pattern),
    compiledRegex: if isExact: nil else: patternToRegex(pattern),
    isExact: isExact
  )
  
  # Cache exact routes for O(1) lookup
  if isExact:
    let exactKey = $httpMethod & ":" & pattern
    app.exactRoutes[exactKey] = route
  
  # Group by method
  if not app.routesByMethod.hasKey(httpMethod):
    app.routesByMethod[httpMethod] = @[]
  app.routesByMethod[httpMethod].add(route)
  
  app.routes.add(route)

# Optimized route finding - O(routes_per_method) instead of O(all_routes)
proc findRoute*(app: App, httpMethod: HttpMethod, path: string): (Route, Table[string, string]) =
  # Quick path for exact matches (static routes)
  let exactKey = $httpMethod & ":" & path
  if app.exactRoutes.hasKey(exactKey):
    return (app.exactRoutes[exactKey], initTable[string, string]())
  
  # Check method-grouped routes
  if app.routesByMethod.hasKey(httpMethod):
    for route in app.routesByMethod[httpMethod]:
      let (matched, params) = matchRoute(route, path)
      if matched:
        return (route, params)
  
  return (nil, initTable[string, string]())