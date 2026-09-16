app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Action
import pf.Elem
import pf.Program

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
		Elem.button({ caption: "Load 100 rows", label: "Load 100 rows", on_press: |_, _| Action.update({ rows: make_rows(100) }) }),
		Elem.button({ caption: "Load 1,000 rows", label: "Load 1000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000) }) }),
		Elem.button({ caption: "Load 10,000 rows", label: "Load 10000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000) }) }),
		Elem.text("Rows: ${state.rows.len().to_str()}"),
		Elem.scroll(Elem.ScrollProps.{ label: "Rows", content: Elem.col({}, state.rows.map(|row| Elem.text("Row ${row.to_str()}"))) }),
	],
)

main : Program(State)
main = Program.run({ init: { rows: [] }, render })
