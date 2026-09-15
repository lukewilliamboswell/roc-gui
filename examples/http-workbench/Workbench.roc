## Request document state and asynchronous HTTP transitions.
import pf.Action
import pf.Http

Workbench := [].{
	State : { url : Str, request : Str, response : Str, error : Str, next_id : U64, active_id : U64, sending : Bool }

	init : State
	init = { url: "", request: "{\"message\":\"hello\"}", response: "", error: "", next_id: 1, active_id: 0, sending: False }

	set_url : State, Str -> State
	set_url = |state, url| { ..state, url, error: "" }

	set_request : State, Str -> State
	set_request = |state, request| { ..state, request, error: "" }

	## Submits a bounded request and suppresses a completion superseded by a
	## later request generation.
	send : State -> Action(State)
	send = |state| {
		id = state.next_id
		url = state.url
		body = state.request
		Action.task({
			pending: { ..state, next_id: id + 1, active_id: id, sending: True, error: "" },
			run: || Http.send!({ method: Post, url, headers: [{ name: "content-type", value: "application/json" }], body, timeout_ms: 2_000, max_response_bytes: 262_144, max_redirects: 3 }),
			resolve: |latest, result| if latest.active_id != id {
				Action.none
			} else {
				match result {
					Ok(response) => Action.update({ ..latest, response: "Status ${response.status.to_str()}\n${response.body}", error: "", sending: False })
					Err(error) => Action.update({ ..latest, response: "", error: describe_error(error), sending: False })
				}
			},
		})
	}
}

describe_error = |error| match error {
	BodyTooLarge => "Response exceeded the configured body limit"
	ConnectFailed => "Connection failed"
	InvalidHeader => "A request header was invalid"
	InvalidRequest => "Request limits were invalid"
	InvalidUrl => "URL was invalid"
	RedirectLimit => "Redirect limit reached"
	Timeout => "Request timed out"
	UnsupportedScheme => "Only HTTP and HTTPS URLs are supported"
	InvalidUtf8 => "Response body was not UTF-8"
}
