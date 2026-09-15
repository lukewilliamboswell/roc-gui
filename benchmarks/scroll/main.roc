app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program exposing [Program]

State : { rows : List(U64) }

make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append($rows.len())
	}
	$rows
}

render = |state| Elem.col(
	{},
	[
		Elem.button({ label: "Load 100 rows", name: "Load 100 rows", on_press: |_, _| Action.update({ rows: make_rows(100) }) }),
		Elem.button({ label: "Load 1,000 rows", name: "Load 1000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000) }) }),
		Elem.button({ label: "Load 10,000 rows", name: "Load 10000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000) }) }),
		Elem.text("Rows: ${state.rows.len().to_str()}"),
		Elem.scroll(Elem.ScrollProps.{ name: "Rows", content: Elem.col({}, state.rows.map(|row| Elem.text("Row ${row.to_str()}"))) }),
	],
)

main : Program(State)
main = Program.run({ init: { rows: [] }, render })
