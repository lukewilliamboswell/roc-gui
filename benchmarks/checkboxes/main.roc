app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Program exposing [Program]

State : { checked : U64, count : U64 }

render : State -> Elem(State)
render = |state| {
	var $items = []
	for _ in List.repeat({}, state.count) {
		index = $items.len()
		$items = $items.append(
			Elem.checkbox(
				Elem.CheckboxProps.{
					label: "Option ${index.to_str()}",
					checked: state.checked == index,
					on_change: |_, event| Action.update({
						..state,
						checked: if event.checked {
							index
						} else {
							state.count
						},
					}),
				},
			),
		)
	}
	Elem.col({}, $items)
}

main : Program(State)
main = Program.run({ init: { checked: 10000, count: 10000 }, render })
