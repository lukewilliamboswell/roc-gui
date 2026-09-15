app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Layout
import pf.Program exposing [Program]

State : { body : Str }
payload = |size| Str.join_with(List.repeat("x", size), "")

render = |state| Layout.col(Elem.ColProps.{ width: Fill, height: Fill, grow: True, padding: 16 }, [
	Layout.row({}, [
		Elem.button({ label: "Load 100 bytes", name: "Load 100 bytes", on_press: |_, _| Action.update({ body: payload(100) }) }),
		Elem.button({ label: "Load 1,000 bytes", name: "Load 1000 bytes", on_press: |_, _| Action.update({ body: payload(1000) }) }),
		Elem.button({ label: "Load 10,000 bytes", name: "Load 10000 bytes", on_press: |_, _| Action.update({ body: payload(10000) }) }),
	]),
	Elem.textarea(Elem.TextareaProps.{ label: "Large request body", value: state.body, on_input: |_, event| Action.update({ body: event.value }), height: Fill, grow: True }),
])

main : Program(State)
main = Program.run({ init: { body: "" }, render, window: { title: "Textarea benchmark", width: 900, height: 650 } })
