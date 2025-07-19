import asyncdispatch, httpcore, tables, re

type
    Context* = ref object
      req*: Request
      res*: Response
      params*: Table[string, string]
      nextCalled*: bool
      middlewareIndex*: int
      pathMiddlewareIndex*: int
      routeMiddlewares*: seq[Handler]
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

    PathMiddleware* = ref object
      pattern*: string
      handler*: Handler
      paramNames*: seq[string]
      compiledRegex*: Regex
      isExact*: bool

    Route* = ref object 
      httpMethod*: HttpMethod
      pattern*: string
      handler*: Handler
      paramNames*: seq[string]
      compiledRegex*: Regex
      isExact*: bool
      middlewares*: seq[Handler]  
      
    Router* = ref object
      routes*: seq[Route]
      middlewares*: seq[Handler]
      pathMiddlewares*: seq[PathMiddleware]
      prefix*: string
    
    App* = ref object
      routes*: seq[Route]
      middlewares*: seq[Handler]
      pathMiddlewares*: seq[PathMiddleware]
      port*: int
      staticRoot*: string
      routesByMethod*: Table[HttpMethod, seq[Route]]
      exactRoutes*: Table[string, Route]
      
    SendFileOptions* = object
      headers*: Table[string, string]
      root*: string
      maxAge*: int
      lastModified*: bool
      etag*: bool
      dotfiles*: string