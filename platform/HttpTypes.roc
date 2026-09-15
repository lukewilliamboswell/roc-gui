HttpTypes := [].{
	Method : [Get, Post]
	Header : { name : Str, value : Str }
	Request : { method : Method, url : Str, headers : List(Header), body : Str, timeout_ms : U64, max_response_bytes : U64, max_redirects : U8 }
	Response : { status : U16, headers : List(Header), body : Str }
	Error : [BodyTooLarge, ConnectFailed, InvalidHeader, InvalidRequest, InvalidUrl, RedirectLimit, Timeout, UnsupportedScheme, InvalidUtf8]
}
