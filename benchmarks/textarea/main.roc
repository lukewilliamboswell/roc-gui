app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

State : { body : Str }

payload = |size| Str.join_with(List.repeat("x", size), "")

render = |state| Elem.col(
	Elem.ColProps.{ width: Fill, height: Fill, grow: True, padding: 16 },
	[
		Elem.row(
			{},
			[
				Elem.button({ caption: "Load 100 bytes", label: "Load 100 bytes", on_press: |_, _| Action.update({ body: payload(100) }) }),
				Elem.button({ caption: "Load 1,000 bytes", label: "Load 1000 bytes", on_press: |_, _| Action.update({ body: payload(1000) }) }),
				Elem.button({ caption: "Load 10,000 bytes", label: "Load 10000 bytes", on_press: |_, _| Action.update({ body: payload(10000) }) }),
			],
		),
		Elem.textarea(Elem.TextareaProps.{ label: "Large request body", value: state.body, on_input: |_, event| Action.update({ body: event.value }), height: Fill, grow: True }),
	],
)

main : Program(State)
main = Program.run({ setup: || { state: { body: "" }, render }, window: { title: "Textarea benchmark", width: 900, height: 650 } })
