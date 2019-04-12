module HTTPx

export startwrite, startread, closewrite, closeread

const DEBUG_LEVEL = Ref(0)

Base.@deprecate escape escapeuri
Base.@deprecate URL URI

using Base64, Sockets, Dates

include("debug.jl")

include("Pairs.jl")                    ;using .Pairs
include("IOExtras.jl")                 ;using .IOExtras
include("Strings.jl")
include("URIs.jl")                     ;using .URIs
include("sniff.jl")
include("multipart.jl")
include("Parsers.jl")                  ;import .Parsers: Headers, Header,
                                                         ParseError
include("ConnectionPool.jl")
include("Messages.jl")                 ;using .Messages
include("cookies.jl")                  ;using .Cookies
include("Streams.jl")                  ;using .Streams

"""

    HTTPx.request(method, url [, headers [, body]]; <keyword arguments>]) -> HTTPx.Response

Send a HTTPx Request Message and receive a HTTPx Response Message.

e.g.
```julia
r = HTTPx.request("GET", "http://httpbin.org/ip")
println(r.status)
println(String(r.body))
```

`headers` can be any collection where
`[string(k) => string(v) for (k,v) in headers]` yields `Vector{Pair}`.
e.g. a `Dict()`, a `Vector{Tuple}`, a `Vector{Pair}` or an iterator.

`body` can take a number of forms:

 - a `String`, a `Vector{UInt8}` or any `T` accepted by `write(::IO, ::T)`
 - a collection of `String` or `AbstractVector{UInt8}` or `IO` streams
   or items of any type `T` accepted by `write(::IO, ::T...)`
 - a readable `IO` stream or any `IO`-like type `T` for which
   `eof(T)` and `readavailable(T)` are defined.

The `HTTPx.Response` struct contains:

 - `status::Int16` e.g. `200`
 - `headers::Vector{Pair{String,String}}`
    e.g. ["Server" => "Apache", "Content-Type" => "text/html"]
 - `body::Vector{UInt8}`, the Response Body bytes
    (empty if a `response_stream` was specified in the `request`).

Functions `HTTPx.get`, `HTTPx.put`, `HTTPx.post` and `HTTPx.head` are defined as
shorthand for `HTTPx.request("GET", ...)`, etc.

`HTTPx.request` and `HTTPx.open` also accept optional keyword parameters.

e.g.
```julia
HTTPx.request("GET", "http://httpbin.org/ip"; retries=4, cookies=true)

HTTPx.get("http://s3.us-east-1.amazonaws.com/"; aws_authorization=true)

conf = (readtimeout = 10,
        pipeline_limit = 4,
        retry = false,
        redirect = false)

HTTPx.get("http://httpbin.org/ip"; conf..)
HTTPx.put("http://httpbin.org/put", [], "Hello"; conf..)
```


URL options

 - `query = nothing`, replaces the query part of `url`.

Streaming options

 - `response_stream = nothing`, a writeable `IO` stream or any `IO`-like
    type `T` for which `write(T, AbstractVector{UInt8})` is defined.
 - `verbose = 0`, set to `1` or `2` for extra message logging.


Connection Pool options

 - `connection_limit = 8`, number of concurrent connections to each host:port.
 - `pipeline_limit = 16`, number of concurrent requests per connection.
 - `reuse_limit = nolimit`, number of times a connection is reused after the
                            first request.
 - `socket_type = TCPSocket`


Timeout options

 - `readtimeout = 60`, close the connection if no data is received for this many
   seconds. Use `readtimeout = 0` to disable.


Retry options

 - `retry = true`, retry idempotent requests in case of error.
 - `retries = 4`, number of times to retry.
 - `retry_non_idempotent = false`, retry non-idempotent requests too. e.g. POST.


Redirect options

 - `redirect = true`, follow 3xx redirect responses.
 - `redirect_limit = 3`, number of times to redirect.
 - `forwardheaders = true`, forward original headers on redirect.


Status Exception options

 - `status_exception = true`, throw `HTTPx.StatusError` for response status >= 300.


SSLContext options

 - `require_ssl_verification = false`, pass `MBEDTLS_SSL_VERIFY_REQUIRED` to
   the mbed TLS library.
   ["... peer must present a valid certificate, handshake is aborted if
     verification failed."](https://tls.mbed.org/api/ssl_8h.html#a5695285c9dbfefec295012b566290f37)
 - `sslconfig = SSLConfig(require_ssl_verification)`


Basic Authentication options

 - basic_authorization=false, add `Authorization: Basic` header using credentials
   from url userinfo.


AWS Authentication options

 - `aws_authorization = false`, enable AWS4 Authentication.
 - `aws_service = split(url.host, ".")[1]`
 - `aws_region = split(url.host, ".")[2]`
 - `aws_access_key_id = ENV["AWS_ACCESS_KEY_ID"]`
 - `aws_secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]`
 - `aws_session_token = get(ENV, "AWS_SESSION_TOKEN", "")`
 - `body_sha256 = digest(MD_SHA256, body)`,
 - `body_md5 = digest(MD_MD5, body)`,


Cookie options

 - `cookies::Union{Bool, Dict{String, String}} = false`, enable cookies, or alternatively,
        pass a `Dict{String, String}` of name-value pairs to manually pass cookies
 - `cookiejar::Dict{String, Set{Cookie}}=default_cookiejar`,


Canonicalization options

 - `canonicalize_headers = false`, rewrite request and response headers in
   Canonical-Camel-Dash-Format.


## Request Body Examples

String body:
```julia
HTTPx.request("POST", "http://httpbin.org/post", [], "post body data")
```

Stream body from file:
```julia
io = open("post_data.txt", "r")
HTTPx.request("POST", "http://httpbin.org/post", [], io)
```

Generator body:
```julia
chunks = ("chunk\$i" for i in 1:1000)
HTTPx.request("POST", "http://httpbin.org/post", [], chunks)
```

Collection body:
```julia
chunks = [preamble_chunk, data_chunk, checksum(data_chunk)]
HTTPx.request("POST", "http://httpbin.org/post", [], chunks)
```

`open() do io` body:
```julia
HTTPx.open("POST", "http://httpbin.org/post") do io
    write(io, preamble_chunk)
    write(io, data_chunk)
    write(io, checksum(data_chunk))
end
```


## Response Body Examples

String body:
```julia
r = HTTPx.request("GET", "http://httpbin.org/get")
println(String(r.body))
```

Stream body to file:
```julia
io = open("get_data.txt", "w")
r = HTTPx.request("GET", "http://httpbin.org/get", response_stream=io)
close(io)
println(read("get_data.txt"))
```

Stream body through buffer:
```julia
io = Base.BufferStream()
@async while !eof(io)
    bytes = readavailable(io))
    println("GET data: \$bytes")
end
r = HTTPx.request("GET", "http://httpbin.org/get", response_stream=io)
close(io)
```

Stream body through `open() do io`:
```julia
r = HTTPx.open("GET", "http://httpbin.org/stream/10") do io
   while !eof(io)
       println(String(readavailable(io)))
   end
end

using HTTPx.IOExtras

HTTPx.open("GET", "https://tinyurl.com/bach-cello-suite-1-ogg") do http
    n = 0
    r = startread(http)
    l = parse(Int, header(r, "Content-Length"))
    open(`vlc -q --play-and-exit --intf dummy -`, "w") do vlc
        while !eof(http)
            bytes = readavailable(http)
            write(vlc, bytes)
            n += length(bytes)
            println("streamed \$n-bytes \$((100*n)÷l)%\\u1b[1A")
        end
    end
end
```


## Request and Response Body Examples

String bodies:
```julia
r = HTTPx.request("POST", "http://httpbin.org/post", [], "post body data")
println(String(r.body))
```

Interfacing with RESTful JSON APIs:
```julia
using JSON
params = Dict("user"=>"RAO...tjN", "token"=>"NzU...Wnp", "message"=>"Hello!")
base_url = "http://api.domain.com"
endpoint = "/1/messages.json"
url = base_url * endpoint
r = HTTPx.request("POST", url,
             ["Content-Type" => "application/json"],
             JSON.json(params))
println(JSON.parse(String(r.body)))
```

Stream bodies from and to files:
```julia
in = open("foo.png", "r")
out = open("foo.jpg", "w")
HTTPx.request("POST", "http://convert.com/png2jpg", [], in, response_stream=out)
```

Stream bodies through: `open() do io`:
```julia
using HTTPx.IOExtras

HTTPx.open("POST", "http://music.com/play") do io
    write(io, JSON.json([
        "auth" => "12345XXXX",
        "song_id" => 7,
    ]))
    r = startread(io)
    @show r.status
    while !eof(io)
        bytes = readavailable(io))
        play_audio(bytes)
    end
end
```
"""
request(method::String, url::URI, headers::Headers, body; kw...)::Response =
    request(HTTPx.stack(;kw...), method, url, headers, body; kw...)
#FIXME consider @nospecialize for `body` ? (other places? in ConnectionPool?)


const nobody = UInt8[]

function request(method, url, h=Header[], b=nobody;
                 headers=h, body=b, query=nothing, kw...)::Response

    uri = URI(url)
    if query !== nothing
        uri = merge(uri, query=query)
    end
    return request(string(method), uri, mkheaders(headers), body; kw...)
end

"""
    HTTPx.open(method, url, [,headers]) do io
        write(io, body)
        [startread(io) -> HTTPx.Response]
        while !eof(io)
            readavailable(io) -> AbstractVector{UInt8}
        end
    end -> HTTPx.Response

The `HTTPx.open` API allows the Request Body to be written to (and/or the
Response Body to be read from) an `IO` stream.


e.g. Streaming an audio file to the `vlc` player:
```julia
HTTPx.open("GET", "https://tinyurl.com/bach-cello-suite-1-ogg") do http
    open(`vlc -q --play-and-exit --intf dummy -`, "w") do vlc
        write(vlc, http)
    end
end
```
"""
open(f::Function, method::String, url, headers=Header[]; kw...)::Response =
    request(method, url, headers, nothing; iofunction=f, kw...)

"""
    HTTPx.openraw(method, url, [, headers])::Tuple{TCPSocket, Response, ByteView}

Open a raw socket that is unmanaged by HTTPx.jl. Useful for doing HTTPx upgrades
to other protocols.  Any bytes of the body read from the socket when reading
headers, is returned as excess bytes in the last tuple argument.

Example of a WebSocket upgrade:
```julia
headers = Dict(
    "Upgrade" => "websocket",
    "Connection" => "Upgrade",
    "Sec-WebSocket-Key" => "dGhlIHNhbXBsZSBub25jZQ==",
    "Sec-WebSocket-Version" => "13")

socket, response, excess = HTTPx.openraw("GET", "ws://echo.websocket.org", headers)

# Write a WebSocket frame
frame = UInt8[0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
write(socket, frame)
```
"""
function openraw(method::String, url, headers=Header[]; kw...)::Tuple{IO, Response}
    socketready = Channel{Tuple{IO, Response}}(0)
    @async HTTPx.open(method, url, headers; kw...) do http
        HTTPx.startread(http)
        socket = http.stream
        put!(socketready, (socket, http.message))
        while(isopen(socket))
            Base.wait_close(socket)
        end
    end
    take!(socketready)
end

"""
    HTTPx.get(url [, headers]; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("GET", ...)`. See [`HTTPx.request`](@ref).
"""
get(a...; kw...) = request("GET", a...; kw...)

"""
    HTTPx.put(url, headers, body; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("PUT", ...)`. See [`HTTPx.request`](@ref).
"""
put(u, h=[], b=""; kw...) = request("PUT", u, h, b; kw...)

"""
    HTTPx.post(url, headers, body; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("POST", ...)`. See [`HTTPx.request`](@ref).
"""
post(u, h=[], b=""; kw...) = request("POST", u, h, b; kw...)

"""
    HTTPx.patch(url, headers, body; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("PATCH", ...)`. See [`HTTPx.request`](@ref).
"""
patch(u, h=[], b=""; kw...) = request("PATCH", u, h, b; kw...)

"""
    HTTPx.head(url; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("HEAD", ...)`. See [`HTTPx.request`](@ref).
"""
head(u; kw...) = request("HEAD", u; kw...)

"""
    HTTPx.delete(url [, headers]; <keyword arguments>) -> HTTPx.Response

Shorthand for `HTTPx.request("DELETE", ...)`. See [`HTTPx.request`](@ref).
"""
delete(a...; kw...) = request("DELETE", a...; kw...)

"""

## Request Execution Stack

The Request Execution Stack is separated into composable layers.

Each layer is defined by a nested type `Layer{Next}` where the `Next`
parameter defines the next layer in the stack.
The `request` method for each layer takes a `Layer{Next}` type as
its first argument and dispatches the request to the next layer
using `request(Next, ...)`.

The example below defines three layers and three stacks each with
a different combination of layers.


```julia
abstract type Layer end
abstract type Layer1{Next <: Layer} <: Layer end
abstract type Layer2{Next <: Layer} <: Layer end
abstract type Layer3 <: Layer end

request(::Type{Layer1{Next}}, data) where Next = "L1", request(Next, data)
request(::Type{Layer2{Next}}, data) where Next = "L2", request(Next, data)
request(::Type{Layer3}, data) = "L3", data

const stack1 = Layer1{Layer2{Layer3}}
const stack2 = Layer2{Layer1{Layer3}}
const stack3 = Layer1{Layer3}
```

```julia
julia> request(stack1, "foo")
("L1", ("L2", ("L3", "foo")))

julia> request(stack2, "bar")
("L2", ("L1", ("L3", "bar")))

julia> request(stack3, "boo")
("L1", ("L3", "boo"))
```

This stack definition pattern gives the user flexibility in how layers are
combined but still allows Julia to do whole-stack compile time optimisations.

e.g. the `request(stack1, "foo")` call above is optimised down to a single
function:
```julia
julia> code_typed(request, (Type{stack1}, String))[1].first
CodeInfo(:(begin
    return (Core.tuple)("L1", (Core.tuple)("L2", (Core.tuple)("L3", data)))
end))
```
"""
abstract type Layer end
include("RedirectRequest.jl");          using .RedirectRequest
include("BasicAuthRequest.jl");         using .BasicAuthRequest
include("AWS4AuthRequest.jl");          using .AWS4AuthRequest
include("CookieRequest.jl");            using .CookieRequest
include("CanonicalizeRequest.jl");      using .CanonicalizeRequest
include("TimeoutRequest.jl");           using .TimeoutRequest
include("MessageRequest.jl");           using .MessageRequest
include("ExceptionRequest.jl");         using .ExceptionRequest
                                        import .ExceptionRequest.StatusError
include("RetryRequest.jl");             using .RetryRequest
include("ConnectionRequest.jl");        using .ConnectionRequest
include("DebugRequest.jl");             using .DebugRequest
include("StreamRequest.jl");            using .StreamRequest
include("ContentTypeRequest.jl");       using .ContentTypeDetection

"""
The `stack()` function returns the default HTTPx Layer-stack type.
This type is passed as the first parameter to the [`HTTPx.request`](@ref) function.

`stack()` accepts optional keyword arguments to enable/disable specific layers
in the stack:
`request(method, args...; kw...) request(stack(;kw...), args...; kw...)`


The minimal request execution stack is:

```julia
stack = MessageLayer{ConnectionPoolLayer{StreamLayer}}
```

The figure below illustrates the full request exection stack and its
relationship with [`HTTPx.Response`](@ref), [`HTTPx.Parsers`](@ref),
[`HTTPx.Stream`](@ref) and the [`HTTPx.ConnectionPool`](@ref).

```
 ┌────────────────────────────────────────────────────────────────────────────┐
 │                                            ┌───────────────────┐           │
 │  HTTPx.jl Request Execution Stack           │ HTTPx.ParsingError ├ ─ ─ ─ ─ ┐ │
 │                                            └───────────────────┘           │
 │                                            ┌───────────────────┐         │ │
 │                                            │ HTTPx.IOError      ├ ─ ─ ─     │
 │                                            └───────────────────┘      │  │ │
 │                                            ┌───────────────────┐           │
 │                                            │ HTTPx.StatusError  │─ ─   │  │ │
 │                                            └───────────────────┘   │       │
 │                                            ┌───────────────────┐      │  │ │
 │     request(method, url, headers, body) -> │ HTTPx.Response     │   │       │
 │             ──────────────────────────     └─────────▲─────────┘      │  │ │
 │                           ║                          ║             │       │
 │   ┌────────────────────────────────────────────────────────────┐      │  │ │
 │   │ request(RedirectLayer,     method, ::URI, ::Headers, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(BasicAuthLayer,    method, ::URI, ::Headers, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(CookieLayer,       method, ::URI, ::Headers, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(CanonicalizeLayer, method, ::URI, ::Headers, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(MessageLayer,      method, ::URI, ::Headers, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(AWS4AuthLayer,             ::URI, ::Request, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(RetryLayer,                ::URI, ::Request, body) │   │       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
 │   │ request(ExceptionLayer,            ::URI, ::Request, body) ├ ─ ┘       │
 │   ├────────────────────────────────────────────────────────────┤      │  │ │
┌┼───┤ request(ConnectionPoolLayer,       ::URI, ::Request, body) ├ ─ ─ ─     │
││   ├────────────────────────────────────────────────────────────┤         │ │
││   │ request(DebugLayer,                ::IO,  ::Request, body) │           │
││   ├────────────────────────────────────────────────────────────┤         │ │
││   │ request(TimeoutLayer,              ::IO,  ::Request, body) │           │
││   ├────────────────────────────────────────────────────────────┤         │ │
││   │ request(StreamLayer,               ::IO,  ::Request, body) │           │
││   └──────────────┬───────────────────┬─────────────────────────┘         │ │
│└──────────────────┼────────║──────────┼───────────────║─────────────────────┘
│                   │        ║          │               ║                   │
│┌──────────────────▼───────────────┐   │  ┌──────────────────────────────────┐
││ HTTPx.Request                     │   │  │ HTTPx.Response                  │ │
││                                  │   │  │                                  │
││ method::String                   ◀───┼──▶ status::Int                    │ │
││ target::String                   │   │  │ headers::Vector{Pair}            │
││ headers::Vector{Pair}            │   │  │ body::Vector{UInt8}            │ │
││ body::Vector{UInt8}              │   │  │                                  │
│└──────────────────▲───────────────┘   │  └───────────────▲────────────────┼─┘
│┌──────────────────┴────────║──────────▼───────────────║──┴──────────────────┐
││ HTTPx.Stream <:IO          ║           ╔══════╗       ║                   │ │
││   ┌───────────────────────────┐       ║   ┌──▼─────────────────────────┐   │
││   │ startwrite(::Stream)      │       ║   │ startread(::Stream)        │ │ │
││   │ write(::Stream, body)     │       ║   │ read(::Stream) -> body     │   │
││   │ ...                       │       ║   │ ...                        │ │ │
││   │ closewrite(::Stream)      │       ║   │ closeread(::Stream)        │   │
││   └───────────────────────────┘       ║   └────────────────────────────┘ │ │
│└───────────────────────────║────────┬──║──────║───────║──┬──────────────────┘
│┌──────────────────────────────────┐ │  ║ ┌────▼───────║──▼────────────────┴─┐
││ HTTPx.Messages                    │ │  ║ │ HTTPx.Parsers                     │
││                                  │ │  ║ │                                  │
││ writestartline(::IO, ::Request)  │ │  ║ │ parse_status_line(bytes, ::Req') │
││ writeheaders(::IO, ::Request)    │ │  ║ │ parse_header_field(bytes, ::Req')│
│└──────────────────────────────────┘ │  ║ └──────────────────────────────────┘
│                            ║        │  ║
│┌───────────────────────────║────────┼──║────────────────────────────────────┐
└▶ HTTPx.ConnectionPool       ║        │  ║                                    │
 │                     ┌──────────────▼────────┐ ┌───────────────────────┐    │
 │ getconnection() ->  │ HTTPx.Transaction <:IO │ │ HTTPx.Transaction <:IO │    │
 │                     └───────────────────────┘ └───────────────────────┘    │
 │                           ║    ╲│╱    ║                  ╲│╱               │
 │                           ║     │     ║                   │                │
 │                     ┌───────────▼───────────┐ ┌───────────▼───────────┐    │
 │              pool: [│ HTTPx.Connection       │,│ HTTPx.Connection       │...]│
 │                     └───────────┬───────────┘ └───────────┬───────────┘    │
 │                           ║     │     ║                   │                │
 │                     ┌───────────▼───────────┐ ┌───────────▼───────────┐    │
 │                     │ Base.TCPSocket <:IO   │ │MbedTLS.SSLContext <:IO│    │
 │                     └───────────────────────┘ └───────────┬───────────┘    │
 │                           ║           ║                   │                │
 │                           ║           ║       ┌───────────▼───────────┐    │
 │                           ║           ║       │ Base.TCPSocket <:IO   │    │
 │                           ║           ║       └───────────────────────┘    │
 └───────────────────────────║───────────║────────────────────────────────────┘
                             ║           ║
 ┌───────────────────────────║───────────║──────────────┐  ┏━━━━━━━━━━━━━━━━━━┓
 │ HTTPx Server               ▼                          │  ┃ data flow: ════▶ ┃
 │                        Request     Response          │  ┃ reference: ────▶ ┃
 └──────────────────────────────────────────────────────┘  ┗━━━━━━━━━━━━━━━━━━┛
```
*See `docs/src/layers`[`.monopic`](http://monodraw.helftone.com).*
"""
function stack(;redirect=true,
                basic_authorization=false,
                aws_authorization=false,
                cookies=false,
                canonicalize_headers=false,
                retry=true,
                status_exception=true,
                readtimeout=0,
                detect_content_type=false,
                verbose=0,
                kw...)

    NoLayer = Union

    (redirect             ? RedirectLayer             : NoLayer){
    (basic_authorization  ? BasicAuthLayer            : NoLayer){
    (detect_content_type  ? ContentTypeDetectionLayer : NoLayer){
    (cookies === true || (cookies isa AbstractDict && !isempty(cookies)) ?
                            CookieLayer               : NoLayer){
    (canonicalize_headers ? CanonicalizeLayer         : NoLayer){
                            MessageLayer{
    (aws_authorization    ? AWS4AuthLayer             : NoLayer){
    (retry                ? RetryLayer                : NoLayer){
    (status_exception     ? ExceptionLayer            : NoLayer){
                            ConnectionPoolLayer{
    (verbose >= 3 ||
     DEBUG_LEVEL[] >= 3   ? DebugLayer                : NoLayer){
    (readtimeout > 0      ? TimeoutLayer              : NoLayer){
                            StreamLayer
    }}}}}}}}}}}}
end

include("download.jl")

include("Servers.jl")                  ;using .Servers; using .Servers: listen
include("Handlers.jl")                 ;using .Handlers; using .Handlers: serve
include("WebSockets.jl")               ;using .WebSockets

import .ConnectionPool: Transaction, Connection

function Base.parse(::Type{T}, str::AbstractString)::T where T <: Message
    buffer = Base.BufferStream()
    write(buffer, str)
    close(buffer)
    m = T()
    http = Stream(m, Transaction(Connection(buffer)))
    m.body = read(http)
    closeread(http)
    return m
end

end # module
