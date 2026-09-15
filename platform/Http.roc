import Host
import HttpTypes

## Bounded asynchronous HTTP request values. Call `send!` only from
## `Action.task` so network work stays off the GUI thread.
Http := [].{
	Method : HttpTypes.Method
	Header : HttpTypes.Header
	Request : HttpTypes.Request
	Response : HttpTypes.Response
	Error : HttpTypes.Error

	## Send one HTTP or HTTPS request with explicit finite limits. At most 64
	## headers, 32 KiB of header data, and 1 MiB of request body are accepted.
	## Timeout is 1..60,000 ms, response limit 1..4 MiB, redirects 0..10.
	send! : Request => Try(Response, Error)
	send! = |request| Host.http_send!(request)
}
