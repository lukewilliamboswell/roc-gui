app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

RowState : { id : U64, value : U64 }
State : { rows : List(RowState) }

make_rows : U64 -> List(RowState)
make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append({ id: $rows.len() + 1, value: 0 })
	}
	$rows
}

find_row : List(RowState), U64 -> RowState
find_row = |rows, id| rows.find_first(|row| row.id == id) ?? crash "row boundary state is missing"

replace_row : State, RowState -> State
replace_row = |state, replacement| {
	{ ..state, rows: state.rows.map(|row| if row.id == replacement.id { replacement } else { row }) }
}

render_row : RowState -> Elem(RowState)
render_row = |row| Layout.row({}, [
	Elem.text("Row ${row.id.to_str()}: ${row.value.to_str()}"),
	Elem.button({
		label: Elem.text("Increment"),
		name: "Increment row ${row.id.to_str()}",
		on_press: |current, _| Action.update({ ..current, value: current.value + 1 }),
	}),
])

render : State -> Elem(State)
render = |state| {
	var $rendered = []
	for row in state.rows {
		id = row.id
		$rendered = $rendered.append(Elem.translate(
			|child| render_row(child),
			|parent| find_row(parent.rows, id),
			|parent, child| replace_row(parent, child),
		))
	}
	Layout.col({}, [
		Layout.row({}, [
			Elem.button({ label: Elem.text("Create 100"), name: "Create 100 rows", on_press: |_, _| Action.update({ rows: make_rows(100) }) }),
			Elem.button({ label: Elem.text("Create 1,000"), name: "Create 1,000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000) }) }),
			Elem.button({ label: Elem.text("Create 10,000"), name: "Create 10,000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000) }) }),
		]),
		Elem.text("Rows: ${state.rows.len().to_str()}"),
		Layout.col({}, $rendered),
	])
}

main : Program(State)
main = Program.run({ init: { rows: [] }, render })
