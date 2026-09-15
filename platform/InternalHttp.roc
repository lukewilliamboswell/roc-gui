import http.Header
import http.Method
import http.Request
import http.Response
import Resource

InternalHttp := [].{
	HostRequest : { client : Resource.HttpClient, method : U8, method_ext : Str, headers : List((Str, Str)), url : Str, body : List(U8), timeout_ms : U64, max_response_bytes : U64, max_redirects : U8 }
	HostResponse : { status : U16, headers : List((Str, Str)), body : List(U8) }

	to_host : Resource.HttpClient, Request, { timeout_ms : U64, max_response_bytes : U64, max_redirects : U8 } -> HostRequest
	to_host = |client, request, config| {
		method = Request.method(request)
		{ client, method: method_code(method), method_ext: method_ext(method), headers: Request.headers(request).map(|{ name, value }| (name, value)), url: Request.uri(request), body: Request.body(request), timeout_ms: config.timeout_ms, max_response_bytes: config.max_response_bytes, max_redirects: config.max_redirects }
	}

	from_host : HostResponse -> Response
	from_host = |response| Response.from_status(response.status).with_headers(response.headers.map(|(name, value)| Header.{ name, value })).with_body(response.body)
}

method_code = |method| match method {
	CONNECT => 0
	DELETE => 1
	QUERY => 2
	GET => 3
	HEAD => 4
	OPTIONS => 5
	PATCH => 6
	POST => 7
	PUT => 8
	TRACE => 9
	Unknown(_) => 10
}

method_ext = |method| match method {
	Unknown(value) => value
	_ => ""
}
