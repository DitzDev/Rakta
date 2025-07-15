import asyncdispatch, httpcore, tables, re

type
    Context* = ref object
      req*: Request
      res*: Response
      params*: Table[string, string]
      nextCalled*: bool
      middlewareIndex*: int
      app*: App
    
    Request* = ref object
      httpMethod*: HttpMethod
      path*: string
      headers*: HttpHeaders
      body*: string
      query*: Table[string, string]
      cookies*: Table[string, string]

    Response* = ref object 
      status*: HttpCode
      headers*: HttpHeaders
      body*: string
      sent*: bool

    Handler* = proc(ctx: Context): Future[void] {.async, gcsafe.}

    Route* = ref object 
      httpMethod*: HttpMethod
      pattern*: string
      handler*: Handler
      paramNames*: seq[string]
      compiledRegex*: Regex
      isExact*: bool

    App* = ref object
      routes*: seq[Route]
      middlewares*: seq[Handler]
      port*: int
      staticRoot*: string
      routesByMethod*: Table[HttpMethod, seq[Route]]  # Method-grouped routes
      exactRoutes*: Table[string, Route]
      
    SendFileOptions* = object
      headers*: Table[string, string]
      root*: string
      maxAge*: int
      lastModified*: bool
      etag*: bool
      dotfiles*: string  # "allow", "deny", "ignore"