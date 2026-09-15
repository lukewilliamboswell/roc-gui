## Request document state and asynchronous HTTP transitions.
import pf.Action
import pf.Http
import http.Request
import http.Response

Workbench := [].{
	State : { url : Str, request : Str, response : Str, error : Str, next_id : U64, active_id : U64, sending : Bool }
	init : State
	init = { url: "", request: "{\"message\":\"hello\"}", response: "", error: "", next_id: 1, active_id: 0, sending: False }
	set_url : State, Str -> State
	set_url = |state, url| { ..state, url, error: "" }
	set_request : State, Str -> State
	set_request = |state, request| { ..state, request, error: "" }

	## Submit with explicitly acquired authority; obsolete generations do no UI work.
	send : State -> Action(State)
	send = |state| {
		id = state.next_id
		request = Request.from_method(POST).with_uri(state.url).add_header("content-type", "application/json").with_body(Str.to_utf8(state.request))
		Action.task({
			pending: { ..state, next_id: id + 1, active_id: id, sending: True, error: "" },
			run: || {
				client = Http.acquire!({})?
				Http.send!(client, { timeout_ms: 2_000, max_response_bytes: 262_144, max_redirects: 3 }, request)
			},
			resolve: |latest, result| if latest.active_id != id Action.none else match result {
				Ok(response) => match Str.from_utf8(Response.body(response)) {
					Ok(body) => Action.update({ ..latest, response: "Status ${Response.status(response).to_str()}\n${body}", error: "", sending: False })
					Err(_) => Action.update({ ..latest, response: "", error: "Response body was not UTF-8", sending: False })
				}
				Err(error) => Action.update({ ..latest, response: "", error: describe_error(error), sending: False })
			},
		})
	}
}

describe_error = |error| match error {
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
