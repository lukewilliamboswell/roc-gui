app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

State : { rows : List(U64) }

make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append($rows.len())
	}
	$rows
}

render = |state| Gui.col(
	{},
	[
		Gui.button({ caption: "Load 100 rows", label: "Load 100 rows", on_press: |_, _| Gui.update({ rows: make_rows(100) }) }),
		Gui.button({ caption: "Load 1,000 rows", label: "Load 1000 rows", on_press: |_, _| Gui.update({ rows: make_rows(1000) }) }),
		Gui.button({ caption: "Load 10,000 rows", label: "Load 10000 rows", on_press: |_, _| Gui.update({ rows: make_rows(10000) }) }),
		Gui.text("Rows: ${state.rows.len().to_str()}"),
		Gui.scroll({ label: "Rows", content: Gui.col({}, state.rows.map(|row| Gui.text("Row ${row.to_str()}"))) }),
	],
)

main : Gui.Program(State)
main = Gui.run({ init: |_access| { rows: [] }, render })
