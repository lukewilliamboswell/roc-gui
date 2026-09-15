## Mounted HTTP Workbench presentation and semantic control identities.
import pf.Action
import pf.Elem
import pf.Gui
import Workbench

View := [].{
	render : Workbench.State -> Elem(Workbench.State)
	render = |state| Elem.col(
		Elem.ColProps.{ label: "HTTP workbench", width: Fill, height: Fill, grow: True, padding: 20, gap: 12 },
		[
			Elem.text("HTTP Workbench"),
			Elem.text_input(Elem.TextInputProps.{ label: "HTTP method", value: state.method, placeholder: "POST", on_change: |current, event| Action.update(Workbench.set_method(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Px(120) }),
			Elem.text_input(Elem.TextInputProps.{ label: "Request URL", value: state.url, placeholder: "https://api.example.com/endpoint", on_change: |current, event| Action.update(Workbench.set_url(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Fill }),
			Elem.text_input(Elem.TextInputProps.{ label: "Query parameters", value: state.query, placeholder: "page=1&limit=100", on_change: |current, event| Action.update(Workbench.set_query(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Fill }),
			Elem.row(Elem.RowProps.{ label: "Request header", width: Fill, gap: 8 }, [
				Elem.text_input(Elem.TextInputProps.{ label: "Header name", value: state.header_name, placeholder: "accept", on_change: |current, event| Action.update(Workbench.set_header_name(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Fill }),
				Elem.text_input(Elem.TextInputProps.{ label: "Header value", value: state.header_value, placeholder: "application/json", on_change: |current, event| Action.update(Workbench.set_header_value(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Fill }),
			]),
			Elem.textarea(Elem.TextareaProps.{ label: "Request body", value: state.request, placeholder: "Enter a JSON object", on_input: |current, event| Action.update(Workbench.set_request(current, event.value)), height: Px(160) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: if state.sending "Send another" else "Send request", label: "Send request", on_press: |current, _| Workbench.send(current), fg: Gui.rgb(0xeeeeea) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Dismiss pending", label: "Dismiss pending response", on_press: |current, _| Workbench.cancel(current), enabled: state.sending }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Retry", label: "Retry request", on_press: |current, _| Workbench.send(current), enabled: Bool.not(state.sending) }),
			if state.error.is_empty() {
				Elem.text("")
			} else {
				Elem.panel(Elem.PanelProps.{ label: "Request error", width: Fill, border_color: Gui.rgb(0xb85c5c) }, [Elem.text(state.error)])
			},
			Elem.text(state.response_status),
			Elem.text("Response headers: ${state.response_header_count.to_str()}"),
			Elem.textarea(Elem.TextareaProps.{ label: "Response headers", value: state.response_headers, placeholder: "Response headers appear here", read_only: True, on_input: |_, _| Action.none, height: Px(100) }),
			Elem.textarea(Elem.TextareaProps.{ label: "Response body", value: state.response, placeholder: "Response appears here", read_only: True, on_input: |_, _| Action.none, height: Fill, grow: True }),
		],
	)
}
