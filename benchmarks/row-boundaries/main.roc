app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Component
import pf.Elem
import pf.Program

RowState : { id : U64, value : U64 }

## Stable ID-indexed storage makes a keyed component lookup independent of
## display order. A removed slot has id zero; live rows keep their original ID.
State : { rows : List(RowState), order : List(U64), selected : U64, compact : Bool }

make_rows : U64 -> List(RowState)
make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append({ id: $rows.len() + 1, value: 0 })
	}
	$rows
}

create_rows : U64 -> State
create_rows = |count| {
	rows = make_rows(count)
	{ rows, order: rows.map(|row| row.id), selected: 0, compact: False }
}

find_row : List(RowState), U64 -> Try(RowState, [Removed])
find_row = |rows, id| {
	if id == 0 {
		return Err(Removed)
	}
	match rows.get(id - 1) {
		Ok(row) => if row.id == id Ok(row) else Err(Removed)
		Err(_) => Err(Removed)
	}
}

replace_row : State, RowState -> State
replace_row = |state, replacement| {
	rows = state.rows.set(replacement.id - 1, replacement) ?? crash "row slot is missing"
	{ ..state, rows }
}

update_every_tenth : State -> State
update_every_tenth = |state| {
	var $rows = state.rows
	var $index = 0
	for id in state.order {
		if $index % 10 == 0 {
			row = find_row($rows, id) ?? crash "ordered row is missing"
			$rows = $rows.set(id - 1, { ..row, value: row.value + 1 }) ?? crash "row slot is missing"
		}
		$index = $index + 1
	}
	{ ..state, rows: $rows }
}

delete_row : State, U64 -> State
delete_row = |state, id| {
	{
		..state,
		rows: state.rows.set(id - 1, { id: 0, value: 0 }) ?? crash "deleted row slot is missing",
		order: state.order.keep_if(|current| current != id),
		selected: if state.selected == id {
			0
		} else {
			state.selected
		},
	}
}

swap_rows : State, U64, U64 -> State
swap_rows = |state, left, right| {
	left_id = state.order.get(left) ?? crash "left swap row is missing"
	right_id = state.order.get(right) ?? crash "right swap row is missing"
	a = state.order.set(left, right_id) ?? crash "left swap index is missing"
	b = a.set(right, left_id) ?? crash "right swap index is missing"
	{ ..state, order: b }
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

render : Component(State), State -> Elem(State)
render = |row_component, state| {
	var $rendered = []
	for id in state.order {
		if state.compact {
			$rendered = $rendered.append(Elem.component(row_component, Id(id)))
		} else {
			$rendered = $rendered.append(
				Elem.row(
					{ label: "Row ${id.to_str()}" },
					[
						Elem.component(row_component, Id(id)),
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
	}
	Elem.col(
		{},
		[
			Elem.row(
				{},
				[
					Elem.button({ caption: "Create 100", label: "Create 100 rows", on_press: |_, _| Action.update(create_rows(100)) }),
					Elem.button({ caption: "Create 1,000", label: "Create 1,000 rows", on_press: |_, _| Action.update(create_rows(1000)) }),
					Elem.button({ caption: "Create 10,000", label: "Create 10,000 rows", on_press: |_, _| Action.update(create_rows(10000)) }),
					Elem.button({ caption: "Update every tenth", label: "Update every tenth row", on_press: |value, _| Action.update(update_every_tenth(value)) }),
					Elem.button({ caption: "Swap", label: "Swap rows 2 and 999", on_press: |value, _| Action.update(swap_rows(value, 1, 998)) }),
					Elem.button({ caption: "Swap small", label: "Swap rows 2 and 99", on_press: |value, _| Action.update(swap_rows(value, 1, 98)) }),
					Elem.button({ caption: "Swap far", label: "Swap rows 2 and 9999", on_press: |value, _| Action.update(swap_rows(value, 1, 9998)) }),
					Elem.button({ caption: if state.compact "Show management" else "Show compact", label: "Toggle compact view", on_press: |value, _| Action.update({ ..value, compact: !value.compact }) }),
				],
			),
			Elem.text("Rows: ${state.order.len().to_str()}"),
			Elem.text("Selection: ${state.selected.to_str()}"),
			Elem.col({}, $rendered),
		],
	)
}

row_get : State, Elem.Key -> Try(RowState, [Removed])
row_get = |parent, key| match Elem.Key.inspect(key) {
	Id(id) => find_row(parent.rows, id)
	_ => Err(Removed)
}

row_set : State, Elem.Key, RowState -> Try(State, [Removed])
row_set = |parent, key, child| match Elem.Key.inspect(key) {
	Id(id) => match find_row(parent.rows, id) {
		Ok(_) => Ok(replace_row(parent, { ..child, id }))
		Err(_) => Err(Removed)
	}
	_ => Err(Removed)
}

setup! : () => { state : State, render : State -> Elem(State) }
setup! = || {
	row_component : Component(State)
	row_component = Component.define!({
		get: row_get,
		set: row_set,
		render: render_row,
	})
	{ state: create_rows(0), render: |state| render(row_component, state) }
}

main : Program(State)
main = Program.run({ setup: setup! })
