app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

RowState : { id : U64, value : I64 }

State : { rows : List(RowState) }

make_rows : U64 -> List(RowState)
make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append({ id: $rows.len() + 1, value: 0 })
	}
	$rows
}

set_row : State, U64, RowState -> State
set_row = |state, index, row| match state.rows.set(index, row) {
	Ok(rows) => { rows: rows }
	Err(_) => crash "scaling row index is out of bounds"
}

render_row : RowState -> Elem(RowState)
render_row = |state| Layout.row({}, [
	Elem.text("Row ${state.id.to_str()}: ${state.value.to_str()}"),
	Elem.button({
		label: Elem.text("+"),
		name: "Row ${state.id.to_str()} increment",
		on_press: |previous, _| Action.update({ ..previous, value: previous.value + 1 }),
	}),
])

render : State -> Elem(State)
render = |state| {
	var $rendered_rows = []
	for _row in state.rows {
		index = $rendered_rows.len()
		$rendered_rows = $rendered_rows.append(Elem.translate(
			render_row,
			|parent| parent.rows.get(index) ?? crash "scaling row is missing",
			|parent, child| set_row(parent, index, child),
		))
	}
	Layout.col({}, [
		Elem.text("Scaling benchmark"),
		Layout.row({}, [
			Elem.button({ label: Elem.text("Build 1,000"), name: "Build 1,000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000) }) }),
			Elem.button({ label: Elem.text("Build 10,000"), name: "Build 10,000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000) }) }),
			Elem.button({ label: Elem.text("Clear"), name: "Clear rows", on_press: |_, _| Action.update({ rows: [] }) }),
		]),
		Elem.text("Rows: ${state.rows.len().to_str()}"),
		Layout.col({}, $rendered_rows),
	])
}

main : Program(State)
main = Program.run({ init: { rows: [] }, render })
