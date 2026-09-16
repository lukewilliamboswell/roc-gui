app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

RowState : { id : U64, value : U64 }

State : { rows : List(RowState), selected : U64 }

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
	{
		..state,
		rows: state.rows.map(
			|row| if row.id == replacement.id {
				replacement
			} else {
				row
			},
		),
	}
}

update_every_tenth : State -> State
update_every_tenth = |state| {
	var $rows = []
	for row in state.rows {
		index = $rows.len()
		next = if index % 10 == 0 {
			{ ..row, value: row.value + 1 }
		} else {
			row
		}
		$rows = $rows.append(next)
	}
	{ ..state, rows: $rows }
}

delete_row : State, U64 -> State
delete_row = |state, id| {
	{
		..state,
		rows: state.rows.keep_if(|row| row.id != id),
		selected: if state.selected == id {
			0
		} else {
			state.selected
		},
	}
}

swap_rows : State, U64, U64 -> State
swap_rows = |state, left, right| {
	left_row = state.rows.get(left) ?? crash "left swap row is missing"
	right_row = state.rows.get(right) ?? crash "right swap row is missing"
	a = state.rows.set(left, right_row) ?? crash "left swap index is missing"
	b = a.set(right, left_row) ?? crash "right swap index is missing"
	{ ..state, rows: b }
}

render_row : RowState -> Elem(RowState)
render_row = |row| Elem.row(
	{},
	[
		Elem.text("Row ${row.id.to_str()}: ${row.value.to_str()}"),
		Elem.button({
			caption: "Increment",
			label: "Increment row ${row.id.to_str()}",
			on_press: |current, _| Action.update({ ..current, value: current.value + 1 }),
		}),
	],
)

render : State -> Elem(State)
render = |state| {
	var $rendered = []
	for row in state.rows {
		id = row.id
		$rendered = $rendered.append(
			Elem.row(
				{},
				[
					Elem.translate(
						|child| render_row(child),
						|parent| find_row(parent.rows, id),
						|parent, child| replace_row(parent, child),
					),
					Elem.button({
						caption: "Select",
						label: "Select row ${id.to_str()}",
						on_press: |current, _| if current.selected == id {
							Action.none
						} else {
							Action.update({ ..current, selected: id })
						},
					}),
					Elem.button({
						caption: "Delete",
						label: "Delete row ${id.to_str()}",
						on_press: |current, _| Action.update(delete_row(current, id)),
					}),
				],
			),
		)
	}
	Elem.col(
		{},
		[
			Elem.row(
				{},
				[
					Elem.button({ caption: "Create 100", label: "Create 100 rows", on_press: |_, _| Action.update({ rows: make_rows(100), selected: 0 }) }),
					Elem.button({ caption: "Create 1,000", label: "Create 1,000 rows", on_press: |_, _| Action.update({ rows: make_rows(1000), selected: 0 }) }),
					Elem.button({ caption: "Create 10,000", label: "Create 10,000 rows", on_press: |_, _| Action.update({ rows: make_rows(10000), selected: 0 }) }),
					Elem.button({ caption: "Update every tenth", label: "Update every tenth row", on_press: |value, _| Action.update(update_every_tenth(value)) }),
					Elem.button({ caption: "Swap", label: "Swap rows 2 and 999", on_press: |value, _| Action.update(swap_rows(value, 1, 998)) }),
					Elem.button({ caption: "Swap small", label: "Swap rows 2 and 99", on_press: |value, _| Action.update(swap_rows(value, 1, 98)) }),
					Elem.button({ caption: "Swap far", label: "Swap rows 2 and 9999", on_press: |value, _| Action.update(swap_rows(value, 1, 9998)) }),
				],
			),
			Elem.text("Rows: ${state.rows.len().to_str()}"),
			Elem.text("Selection: ${state.selected.to_str()}"),
			Elem.col({}, $rendered),
		],
	)
}

main : Program(State)
main = Program.run({ init: { rows: [], selected: 0 }, render })
