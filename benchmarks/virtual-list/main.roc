app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Layout
import pf.Program exposing [Program]

State : { rows : List(U64), selected : U64 }

make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append($rows.len())
	}
	$rows
}

render = |state| Layout.col(
	Elem.ColProps.{ width: Fill, height: Fill, grow: True },
	[
		Layout.row(
			{},
			[
				Elem.button({ label: "Load 100 rows", name: "Load 100 rows", on_press: |_, _| Action.update({ rows: make_rows(100), selected: 100 }) }),
				Elem.button({ label: "Load 1,000 rows", name: "Load 1000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000), selected: 1000 }) }),
				Elem.button({ label: "Load 10,000 rows", name: "Load 10000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000), selected: 10000 }) }),
			],
		),
		Elem.text("Rows: ${state.rows.len().to_str()}"),
		Elem.text("Selected: ${state.selected.to_str()}"),
		Elem.virtual_list(
			Elem.VirtualListProps.{
				name: "Rows",
				row_height: 28,
				items: state.rows.map(|row| Elem.VirtualListItem.{ key: row, content: Elem.button({ label: "Virtual row ${row.to_str()}", name: "Select virtual row ${row.to_str()}", on_press: |current, _| Action.update({ ..current, selected: row }) }) }),
			},
		),
	],
)

main : Program(State)
main = Program.run({ init: { rows: [], selected: 0 }, render })
