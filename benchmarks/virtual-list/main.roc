app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }

import pf.Gui

State : { rows : List(U64), selected : U64 }

make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append($rows.len())
	}
	$rows
}

render = |state| Gui.col(
	{ width: Fill, height: Fill, grow: True },
	[
		Gui.row(
			{},
			[
				Gui.button({ caption: "Load 100 rows", label: "Load 100 rows", on_press: |_, _| Gui.Action.update({ rows: make_rows(100), selected: 100 }) }),
				Gui.button({ caption: "Load 1,000 rows", label: "Load 1000 rows", on_press: |_, _| Gui.Action.update({ rows: make_rows(1000), selected: 1000 }) }),
				Gui.button({ caption: "Load 10,000 rows", label: "Load 10000 rows", on_press: |_, _| Gui.Action.update({ rows: make_rows(10000), selected: 10000 }) }),
			],
		),
		Gui.text("Rows: ${state.rows.len().to_str()}"),
		Gui.text("Selected: ${state.selected.to_str()}"),
		Gui.virtual_list({
			label: "Rows",
			row_height: 28,
			items: state.rows.map(|row| { key: row, content: Gui.button({ caption: "Virtual row ${row.to_str()}", label: "Select virtual row ${row.to_str()}", on_press: |current, _| Gui.Action.update({ ..current, selected: row }) }) }),
		}),
	],
)

main : Gui.Program(State)
main = Gui.run({ init: |_access| { rows: [], selected: 0 }, render })
