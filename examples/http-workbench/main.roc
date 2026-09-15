app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Layout
import pf.Program exposing [Program]

State : { request : Str, response : Str, error : Str }

preview = |state| if state.request.trim().is_empty() {
	Action.update({ ..state, error: "Request body is required", response: "" })
} else if !state.request.starts_with("{") or !state.request.ends_with("}") {
	Action.update({ ..state, error: "Request body must be a JSON object", response: "" })
} else {
	Action.update({ ..state, error: "", response: "HTTP/1.1 200 Preview\nContent-Type: application/json\n\n{\"accepted\":true}" })
}

render = |state| Layout.col(Elem.ColProps.{ label: "HTTP workbench", width: Fill, height: Fill, grow: True, padding: 20, gap: 12 }, [
	Elem.text("HTTP Workbench"),
	Elem.text("Request body"),
	Elem.textarea(Elem.TextareaProps.{ label: "Request body", value: state.request, placeholder: "Enter a JSON object", on_input: |current, event| Action.update({ ..current, request: event.value, error: "" }), height: Px(200) }),
	Elem.action_button(Elem.ActionButtonProps.{ caption: "Preview request", label: "Preview request", on_press: |current, _| preview(current), fg: Gui.rgb(0xeeeeea) }),
	if state.error.is_empty() { Elem.text("") } else { Elem.panel(Elem.PanelProps.{ label: "Request error", width: Fill, border_color: Gui.rgb(0xb85c5c) }, [Elem.text(state.error)]) },
	Elem.text("Response"),
	Elem.textarea(Elem.TextareaProps.{ label: "Response body", value: state.response, placeholder: "Preview output appears here", read_only: True, on_input: |_, _| Action.none, height: Fill, grow: True }),
])

main : Program(State)
main = Program.run({ init: { request: "{\"message\":\"hello\"}", response: "", error: "" }, render, window: { title: "HTTP Workbench", width: 840, height: 680 } })
