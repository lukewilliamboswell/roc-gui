app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui

RowState : { id : U64, value : U64 }

State : { next_id : U64, rows : List(RowState), selected : U64 }

make_rows : U64, U64 -> List(RowState)
make_rows = |first_id, count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append({ id: first_id + $rows.len(), value: 0 })
	}
	$rows
}

create : U64 -> State
create = |count| { next_id: count + 1, rows: make_rows(1, count), selected: 0 }

append_rows : State, U64 -> State
append_rows = |state, count| {
	added = make_rows(state.next_id, count)
	{ ..state, next_id: state.next_id + count, rows: state.rows.concat(added) }
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
	var $rows = []
	for row in state.rows {
		if row.id != id {
			$rows = $rows.append(row)
		}
	}
	{
		..state,
		rows: $rows,
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

render_row : RowState -> Gui.Elem(State)
render_row = |row| Gui.row(
	{},
	[
		Gui.text("Row ${row.id.to_str()}: ${row.value.to_str()}"),
		Gui.button({
			caption: "Select",
			label: "Select row ${row.id.to_str()}",
			on_press: |state, _| if state.selected == row.id {
				Gui.Action.none
			} else {
				Gui.Action.update({ ..state, selected: row.id })
			},
		}),
		Gui.button({
			caption: "Delete",
			label: "Delete row ${row.id.to_str()}",
			on_press: |state, _| Gui.Action.update(delete_row(state, row.id)),
		}),
	],
)

render : State -> Gui.Elem(State)
render = |state| {
	var $rendered = []
	for row in state.rows {
		$rendered = $rendered.append(render_row(row))
	}
	Gui.col(
		{},
		[
			Gui.row(
				{},
				[
					Gui.button({ caption: "Create 100", label: "Create 100 rows", on_press: |_, _| Gui.Action.update(create(100)) }),
					Gui.button({ caption: "Create 1,000", label: "Create 1,000 rows", on_press: |_, _| Gui.Action.update(create(1000)) }),
					Gui.button({ caption: "Create 10,000", label: "Create 10,000 rows", on_press: |_, _| Gui.Action.update(create(10000)) }),
					Gui.button({ caption: "Create 100,000", label: "Create 100,000 rows", on_press: |_, _| Gui.Action.update(create(100000)) }),
					Gui.button({ caption: "Append 1,000", label: "Append 1,000 rows", on_press: |value, _| Gui.Action.update(append_rows(value, 1000)) }),
					Gui.button({ caption: "Update every tenth", label: "Update every tenth row", on_press: |value, _| Gui.Action.update(update_every_tenth(value)) }),
					Gui.button({ caption: "Swap", label: "Swap rows 2 and 999", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 998)) }),
					Gui.button({ caption: "Swap small", label: "Swap rows 2 and 99", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 98)) }),
					Gui.button({ caption: "Swap far", label: "Swap rows 2 and 9999", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 9998)) }),
					Gui.button({ caption: "Clear", label: "Clear rows", on_press: |value, _| Gui.Action.update({ ..value, rows: [], selected: 0 }) }),
				],
			),
			Gui.text("Rows: ${state.rows.len().to_str()}"),
			Gui.text("Selection: ${state.selected.to_str()}"),
			Gui.col({}, $rendered),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({ init: |_access| { next_id: 1, rows: [], selected: 0 }, render })
