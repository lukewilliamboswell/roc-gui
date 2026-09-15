## Request document state and asynchronous HTTP transitions.
import pf.Action
import pf.Http
import http.Request
import http.Response

Workbench := [].{
	State : { method : Str, url : Str, query : Str, header_name : Str, header_value : Str, request : Str, response_status : Str, response_header_count : U64, response_headers : Str, response : Str, error : Str, next_id : U64, active_id : U64, sending : Bool }
	init : State
	init = { method: "POST", url: "", query: "", header_name: "content-type", header_value: "application/json", request: "{\"message\":\"hello\"}", response_status: "No response", response_header_count: 0, response_headers: "", response: "", error: "", next_id: 1, active_id: 0, sending: False }
	set_method = |state, method| { ..state, method, error: "" }
	set_url : State, Str -> State
	set_url = |state, url| { ..state, url, error: "" }
	set_query = |state, query| { ..state, query, error: "" }
	set_header_name = |state, name| { ..state, header_name: name, error: "" }
	set_header_value = |state, value| { ..state, header_value: value, error: "" }
	set_request : State, Str -> State
	set_request = |state, request| { ..state, request, error: "" }

	## Submit with explicitly acquired authority; obsolete generations do no UI work.
	send : State -> Action(State)
	send = |state| match state.method {
		"GET" => send_method(state, GET)
		"DELETE" => send_method(state, DELETE)
		"PATCH" => send_method(state, PATCH)
		"POST" => send_method(state, POST)
		"PUT" => send_method(state, PUT)
		_ => Action.update({ ..state, error: "Unsupported HTTP method", sending: False })
	}

	send_method = |state, method| {
		id = state.next_id
		url = if state.query.is_empty() state.url else "${state.url}?${state.query}"
		base_request = Request.from_method(method).with_uri(url).with_body(Str.to_utf8(state.request))
		request = if state.header_name.is_empty() base_request else base_request.add_header(state.header_name, state.header_value)
		Action.task({
			pending: { ..state, next_id: id + 1, active_id: id, sending: True, error: "" },
			run: || {
				client = Http.acquire!()?
				Http.send!(client, { timeout_ms: 2_000, max_response_bytes: 262_144, max_redirects: 3 }, request)
			},
			resolve: |latest, result| if latest.active_id != id Action.none else match result {
				Ok(response) => match Str.from_utf8(Response.body(response)) {
					Ok(body) => Action.update({ ..latest, response_status: "Status ${Response.status(response).to_str()}", response_header_count: Response.headers(response).len(), response_headers: Str.join_with(Response.headers(response).map(|header| "${header.name}: ${header.value}"), "\n"), response: "Status ${Response.status(response).to_str()}\n${body}", error: "", sending: False })
					Err(_) => Action.update({ ..latest, response: "", error: "Response body was not UTF-8", sending: False })
				}
				Err(error) => Action.update({ ..latest, response: "", error: describe_error(error), sending: False })
			},
		})
	}

	cancel : State -> Action(State)
	cancel = |state| Action.update({ ..state, active_id: state.next_id, next_id: state.next_id + 1, sending: False, error: "Pending response dismissed" })
}

describe_error = |error| match error {
	AcquireHttpErr(reason) => describe_reason(reason)
	SendHttpErr(reason) => describe_reason(reason)
}

describe_reason = |error| match error {
	AccessDenied => "HTTP access was not granted for this origin"
	BodyTooLarge => "Response exceeded the configured body limit"
	ConnectFailed => "Connection failed"
	InvalidCapability => "HTTP capability was no longer valid"
	InvalidHeader => "A request header was invalid"
	InvalidRequest => "Request limits were invalid"
	InvalidUrl => "URL was invalid"
	RedirectLimit => "Redirect limit reached"
	Timeout => "Request timed out"
	UnsupportedScheme => "Only HTTP and HTTPS URLs are supported"
}
