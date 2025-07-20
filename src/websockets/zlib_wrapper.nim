{.passL: "-lz".}

const
  Z_OK* = 0
  Z_STREAM_END* = 1
  Z_NEED_DICT* = 2
  Z_ERRNO* = -1
  Z_STREAM_ERROR* = -2
  Z_DATA_ERROR* = -3
  Z_MEM_ERROR* = -4
  Z_BUF_ERROR* = -5
  Z_VERSION_ERROR* = -6
  
  Z_NO_FLUSH* = 0
  Z_PARTIAL_FLUSH* = 1
  Z_SYNC_FLUSH* = 2
  Z_FULL_FLUSH* = 3
  Z_FINISH* = 4
  Z_BLOCK* = 5
  Z_TREES* = 6
  
  Z_DEFAULT_COMPRESSION* = -1
  Z_NO_COMPRESSION* = 0
  Z_BEST_SPEED* = 1
  Z_BEST_COMPRESSION* = 9
  Z_DEFAULT_STRATEGY* = 0
  
  Z_DEFLATED* = 8

type
  ZStream* {.importc: "z_stream", header: "<zlib.h>", final.} = object
    nextIn* {.importc: "next_in".}: ptr uint8
    availIn* {.importc: "avail_in".}: cuint
    totalIn* {.importc: "total_in".}: culong
    nextOut* {.importc: "next_out".}: ptr uint8
    availOut* {.importc: "avail_out".}: cuint
    totalOut* {.importc: "total_out".}: culong
    msg* {.importc: "msg".}: cstring
    state* {.importc: "state".}: pointer
    zalloc* {.importc: "zalloc".}: pointer
    zfree* {.importc: "zfree".}: pointer
    opaque* {.importc: "opaque".}: pointer
    dataType* {.importc: "data_type".}: cint
    adler* {.importc: "adler".}: culong
    reserved* {.importc: "reserved".}: culong

proc deflateInit2*(strm: var ZStream, level: cint, meth: cint, windowBits: cint, memLevel: cint, strategy: cint): cint {.importc, header: "<zlib.h>".}
proc inflateInit2*(strm: var ZStream, windowBits: cint): cint {.importc, header: "<zlib.h>".}
proc deflate*(strm: var ZStream, flush: cint): cint {.importc, header: "<zlib.h>".}
proc inflate*(strm: var ZStream, flush: cint): cint {.importc, header: "<zlib.h>".}
proc deflateEnd*(strm: var ZStream): cint {.importc, header: "<zlib.h>".}
proc inflateEnd*(strm: var ZStream): cint {.importc, header: "<zlib.h>".}