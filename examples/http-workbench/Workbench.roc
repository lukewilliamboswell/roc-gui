## Request document state, the authority the bench currently holds, and the
## asynchronous HTTP transitions between them.
import pf.Program
import pf.Action
import pf.Http
import http.Request
import http.Response

## What the bench knows about its own HTTP authority, which is scoped to one
## exact origin and can only be learned by exercising it.
##
## `Unexercised` is the honest first-frame answer: the host may or may not have
## granted this origin, and nothing short of a send can tell. `Granted` and
## `Refused` each remember *which* origin the verdict was about, because the
## URL field can be edited to point somewhere the verdict does not cover.
Authority : [Unexercised, Granted(Str), Refused(Str)]

Workbench := [].{
	Authority : Authority
	State : State
	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Program.Access -> State
	init = |access| {
		access,
		method: "POST",
		url: "",
		query: "",
		header_name: "content-type",
		header_value: "application/json",
		request: "{\"message\":\"hello\"}",
		response_status: "No response",
		response_header_count: 0,
		response_headers: "",
		response: "",
		response_bytes: 0,
		error: "",
		remedy: "",
		authority: Unexercised,
		next_id: 1,
		active_id: 0,
		sending: False,
	}
	set_method = |state, method| clear_error({ ..state, method })
	set_url : State, Str -> State
	set_url = |state, url| clear_error({ ..state, url })
	set_query = |state, query| clear_error({ ..state, query })
	set_header_name = |state, name| clear_error({ ..state, header_name: name })
	set_header_value = |state, value| clear_error({ ..state, header_value: value })
	set_request : State, Str -> State
	set_request = |state, request| clear_error({ ..state, request })

	## The origin the *next* send will ask for, read straight off the URL field.
	## The bench shows this before anything is sent so a person can see which
	## authority is about to be exercised rather than discovering it afterwards.
	origin_of : Str -> Str
	origin_of = origin_of

	## Submit with explicitly acquired authority; obsolete generations do no UI work.
	send : State -> Action(State)
	send = |state| match state.method {
		"GET" => send_method(state, GET)
		"DELETE" => send_method(state, DELETE)
		"PATCH" => send_method(state, PATCH)
		"POST" => send_method(state, POST)
		"PUT" => send_method(state, PUT)
		_ => Action.update({
			..state,
			error: "Unsupported HTTP method",
			remedy: "The bench sends GET, POST, PUT, PATCH, and DELETE.",
			sending: False,
		})
	}

	cancel : State -> Action(State)
	cancel = |state| if state.sending {
		Action.update({
			..state,
			active_id: state.next_id,
			next_id: state.next_id + 1,
			sending: False,
			error: "Pending response dismissed",
			remedy: "The request is still in flight; its reply will be ignored.",
		})
	} else {
		Action.none
	}
}

State : {
	access : Program.Access,
	method : Str,
	url : Str,
	query : Str,
	header_name : Str,
	header_value : Str,
	request : Str,
	response_status : Str,
	response_header_count : U64,
	response_headers : Str,
	response : Str,
	response_bytes : U64,
	error : Str,
	remedy : Str,
	authority : Authority,
	next_id : U64,
	active_id : U64,
	sending : Bool,
}

clear_error = |state| { ..state, error: "", remedy: "" }

## `http://host:port` from a URL, or the empty string when the field does not
## yet name one. Splitting on `/` is enough: the origin is everything before the
## third separator, and anything else is not a URL the bench can send.
origin_of = |url| {
	parts = Str.split_on(url, "/")
	scheme = parts.get(0) ?? ""
	host = parts.get(2) ?? ""
	if (scheme == "http:" or scheme == "https:") and !Str.is_empty(host) {
		"${scheme}//${host}"
	} else {
		""
	}
}

send_method = |state, method| {
	id = state.next_id
	origin = origin_of(state.url)
	url = if state.query.is_empty() state.url else "${state.url}?${state.query}"
	base_request = Request.from_method(method).with_uri(url).with_body(Str.to_utf8(state.request))
	request = if state.header_name.is_empty() base_request else base_request.add_header(state.header_name, state.header_value)
	Action.task({
		pending: { ..state, next_id: id + 1, active_id: id, sending: True, error: "", remedy: "" },
		run: || {
			client = Http.acquire!(state.access)?
			client.send!(Http.Config.{ timeout_ms: 2_000, max_response_bytes: 262_144 }, request)
		},
		resolve: |latest, result| if latest.active_id != id Action.none else match result {
			Ok(response) => {
				bytes = Response.body(response)
				headers = Response.headers(response)
				status_line = "Status ${Response.status(response).to_str()}"
				match Str.from_utf8(bytes) {
				Ok(body) => Action.update({
					..latest,
					response_status: status_line,
					response_header_count: headers.len(),
					response_headers: Str.join_with(headers.map(|header| "${header.name}: ${header.value}"), "\n"),
					response: body,
					response_bytes: bytes.len(),
					authority: Granted(origin),
					error: "",
					remedy: "",
					sending: False,
				})
				Err(_) => Action.update({
					..latest,
					response: "",
					response_bytes: 0,
					response_status: "No response",
					response_header_count: 0,
					response_headers: "",
					authority: Granted(origin),
					error: "Response body was not UTF-8",
					remedy: "The bench presents text. This reply is not decodable as UTF-8.",
					sending: False,
				})
				}
			}
			Err(error) => {
				failure = describe(error, origin)
				Action.update({
					..latest,
					response: "",
					response_bytes: 0,
					response_status: "No response",
					response_header_count: 0,
					response_headers: "",
					authority: if failure.denied Refused(origin) else latest.authority,
					error: failure.message,
					remedy: failure.remedy,
					sending: False,
				})
			}
		},
	})
}

describe = |error, origin| match error {
	AcquireHttpErr(reason) => describe_reason(reason, origin)
	SendHttpErr(reason) => describe_reason(reason, origin)
}

## Every failure carries what happened, what a person can do about it, and
## whether it was the authority itself that said no. A refusal is the one case
## that changes what the bench claims to hold, and it names the exact grant that
## would answer it, so the next step is a command and not a guess.
describe_reason = |error, origin| match error {
	AccessDenied => {
		message: "HTTP access was not granted for this origin",
		remedy: "Restart with --host-cap-http-origin ${if Str.is_empty(origin) "<origin>" else origin}",
		denied: True,
	}
	BodyTooLarge => {
		message: "Response exceeded the configured body limit",
		remedy: "The bench reads at most 256 KiB of body. Ask the service for less.",
		denied: False,
	}
	ConnectFailed => {
		message: "Connection failed",
		remedy: "Nothing answered at ${if Str.is_empty(origin) "that origin" else origin}. Check the service is running.",
		denied: False,
	}
	InvalidCapability => {
		message: "HTTP capability was no longer valid",
		remedy: "The handle does not name a client. Acquire one before sending.",
		denied: True,
	}
	Revoked => {
		message: "HTTP authority was withdrawn",
		remedy: "Someone took this destination back. Restart the bench to ask for it again.",
		denied: True,
	}
	InvalidHeader => {
		message: "A request header was invalid",
		remedy: "A header name is a token: letters, digits, and dashes, with no spaces.",
		denied: False,
	}
	InvalidRequest => {
		message: "Request limits were invalid",
		remedy: "The timeout, body limit, or redirect limit was out of range.",
		denied: False,
	}
	InvalidUrl => {
		message: "URL was invalid",
		remedy: "Give an absolute URL, for example http://127.0.0.1:38191/echo",
		denied: False,
	}
	RedirectLimit => {
		message: "Redirect limit reached",
		remedy: "The bench follows at most three redirects before it stops.",
		denied: False,
	}
	Timeout => {
		message: "Request timed out",
		remedy: "The bench waits two seconds. Retry, or ask for a smaller reply.",
		denied: False,
	}
	UnsupportedScheme => {
		message: "Only HTTP and HTTPS URLs are supported",
		remedy: "The granted authority covers one http:// or https:// origin only.",
		denied: False,
	}
}
