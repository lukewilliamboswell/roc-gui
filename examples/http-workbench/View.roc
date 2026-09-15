## Mounted HTTP Workbench presentation and semantic control identities.
import pf.Action
import pf.Elem
import pf.Gui
import pf.Layout
import Workbench

View := [].{
	render : Workbench.State -> Elem(Workbench.State)
	render = |state| Layout.col(
		Elem.ColProps.{ label: "HTTP workbench", width: Fill, height: Fill, grow: True, padding: 20, gap: 12 },
		[
			Elem.text("HTTP Workbench"),
			Elem.text_input(Elem.TextInputProps.{ label: "Request URL", value: state.url, placeholder: "https://api.example.com/endpoint", on_change: |current, event| Action.update(Workbench.set_url(current, event.value)), on_submit: |current, _| Workbench.send(current), width: Fill }),
			Elem.textarea(Elem.TextareaProps.{ label: "Request body", value: state.request, placeholder: "Enter a JSON object", on_input: |current, event| Action.update(Workbench.set_request(current, event.value)), height: Px(160) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: if state.sending "Send another" else "Send request", label: "Send request", on_press: |current, _| Workbench.send(current), fg: Gui.rgb(0xeeeeea) }),
			if state.error.is_empty() {
				Elem.text("")
			} else {
				Elem.panel(Elem.PanelProps.{ label: "Request error", width: Fill, border_color: Gui.rgb(0xb85c5c) }, [Elem.text(state.error)])
			},
			Elem.textarea(Elem.TextareaProps.{ label: "Response body", value: state.response, placeholder: "Response appears here", read_only: True, on_input: |_, _| Action.none, height: Fill, grow: True }),
		],
	)
}
