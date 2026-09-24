app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui

State : { checked : U64, count : U64 }

render : State -> Gui.Elem(State)
render = |state| {
	var $items = []
	for _ in List.repeat({}, state.count) {
		index = $items.len()
		$items = $items.append(
			Gui.checkbox({
				label: "Option ${index.to_str()}",
				checked: state.checked == index,
				on_change: |_, event| Gui.Action.update({
					..state,
					checked: if event.checked {
						index
					} else {
						state.count
					},
				}),
			}),
		)
	}
	Gui.col({}, $items)
}

main : Gui.Program(State)
main = Gui.run({ init: |_access| { checked: 10000, count: 10000 }, render })
