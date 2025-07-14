import asyncdispatch, httpcore, json, strutils, tables
import types

proc status*(ctx: Context, code: HttpCode): Context =
  ctx.res.status = code
  return ctx

proc setHeader*(ctx: Context, name: string, value: string): Context =
  ctx.res.headers[name] = value
  return ctx

proc setCookie*(ctx: Context, name: string, value: string, httpOnly: bool = false, secure: bool = false, sameSite: string = "Lax"): Context =
  var cookieValue = name & "=" & value
  if httpOnly:
    cookieValue.add("; HttpOnly")
  if secure:
    cookieValue.add("; Secure")
  cookieValue.add("; SameSite=" & sameSite)
  
  if ctx.res.headers.hasKey("Set-Cookie"):
    ctx.res.headers["Set-Cookie"] = ctx.res.headers["Set-Cookie"] & ", " & cookieValue
  else:
    ctx.res.headers["Set-Cookie"] = cookieValue
  return ctx

proc send*(ctx: Context, content: string): Future[void] {.async.} =
  if ctx.res.sent:
    return
  ctx.res.body = content
  ctx.res.sent = true

proc json*(ctx: Context, data: JsonNode): Future[void] {.async.} =
  if ctx.res.sent:
    return
  discard ctx.setHeader("Content-Type", "application/json")
  ctx.res.body = $data
  ctx.res.sent = true

proc jsonBody*(ctx: Context): JsonNode =
  try:
    return parseJson(ctx.req.body)
  except:
    return newJNull()

proc getCookie*(ctx: Context, name: string): string =
  if ctx.req.cookies.hasKey(name):
    return ctx.req.cookies[name]
  return ""

proc getQuery*(ctx: Context, name: string): string =
  if ctx.req.query.hasKey(name):
    return ctx.req.query[name]
  return ""

proc getParam*(ctx: Context, name: string): string =
  if ctx.params.hasKey(name):
    return ctx.params[name]
  return ""