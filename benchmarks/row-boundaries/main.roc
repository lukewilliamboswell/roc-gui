app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }

import pf.Gui

RowState : { id : U64, key : Gui.Key, value : U64 }

## Persistent ID-indexed storage copies only a bounded radix path on local
## updates. Display ordering belongs to the parent and is shared by row edits.
State : { rows : Gui.Index(RowState), order : List(U64), selected : U64, compact : Bool, memoized : Bool }

create_rows : U64 -> State
create_rows = |count| {
	var $rows = Gui.Index.empty
	var $order = []
	for _ in List.repeat({}, count) {
		id = $order.len() + 1
		$rows = Gui.Index.set($rows, id, { id, key: Gui.Key.id(id), value: 0 })
		$order = $order.append(id)
	}
	{ rows: $rows, order: $order, selected: 0, compact: False, memoized: True }
}

find_row : Gui.Index(RowState), U64 -> Try(RowState, [Removed])
find_row = |rows, id| Gui.Index.get(rows, id).map_err(|_| Removed)

replace_row : State, RowState -> State
replace_row = |state, replacement| {
	rows = Gui.Index.set(state.rows, replacement.id, replacement)
	{ ..state, rows }
}

update_every_tenth : State -> State
update_every_tenth = |state| {
	var $rows = state.rows
	var $index = 0
	for id in state.order {
		if $index % 10 == 0 {
			row = find_row($rows, id) ?? crash "ordered row is missing"
			$rows = Gui.Index.set($rows, id, { ..row, value: row.value + 1 })
		}
		$index = $index + 1
	}
	{ ..state, rows: $rows }
}

delete_row : State, U64 -> State
delete_row = |state, id| {
	{
		..state,
		rows: Gui.Index.remove(state.rows, id),
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

render_row : RowState -> Gui.Elem(RowState)
render_row = |row| Gui.row(
	{},
	[
		Gui.text("Row ${row.id.to_str()}: ${row.value.to_str()}"),
		Gui.button({
			caption: "Increment",
			label: "Increment row ${row.id.to_str()}",
			on_press: |current, _| Gui.Action.update({ ..current, value: current.value + 1 }),
		}),
	],
)

render : State -> Gui.Elem(State)
render = |state| {
	var $rendered = []
	for id in state.order {
		row = find_row(state.rows, id) ?? crash "ordered row is missing"
		boundary = Gui.try_translate(
			render_row,
			{
				key: row.key,
				get: |parent| find_row(parent.rows, id),
				set: |parent, child| match find_row(parent.rows, id) {
					Ok(_) => Ok(replace_row(parent, { ..child, id }))
					Err(_) => Err(Removed)
				},
				memo: if state.memoized Some(|previous, next| previous == next) else None,
			},
		)
		if state.compact {
			$rendered = $rendered.append(boundary)
		} else {
			$rendered = $rendered.append(
				Gui.row(
					{ label: "Row ${id.to_str()}" },
					[
						boundary,
						Gui.button({
							caption: "Select",
							label: "Select row ${id.to_str()}",
							on_press: |current, _| if current.selected == id {
								Gui.Action.none
							} else {
								Gui.Action.update({ ..current, selected: id })
							},
						}),
						Gui.button({
							caption: "Delete",
							label: "Delete row ${id.to_str()}",
							on_press: |current, _| Gui.Action.update(delete_row(current, id)),
						}),
					],
				),
			)
		}
	}
	Gui.col(
		{},
		[
			Gui.row(
				{},
				[
					Gui.button({ caption: "Create 100", label: "Create 100 rows", on_press: |latest, _| Gui.Action.update({ ..create_rows(100), memoized: latest.memoized }) }),
					Gui.button({ caption: "Create 1,000", label: "Create 1,000 rows", on_press: |latest, _| Gui.Action.update({ ..create_rows(1000), memoized: latest.memoized }) }),
					Gui.button({ caption: "Create 10,000", label: "Create 10,000 rows", on_press: |latest, _| Gui.Action.update({ ..create_rows(10000), memoized: latest.memoized }) }),
					Gui.button({ caption: "Memoized", label: "Use memoized rows", on_press: |latest, _| Gui.Action.update({ ..latest, memoized: True }) }),
					Gui.button({ caption: "Unmemoized", label: "Use unmemoized rows", on_press: |latest, _| Gui.Action.update({ ..latest, memoized: False }) }),
					Gui.button({ caption: "Update every tenth", label: "Update every tenth row", on_press: |value, _| Gui.Action.update(update_every_tenth(value)) }),
					Gui.button({ caption: "Swap", label: "Swap rows 2 and 999", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 998)) }),
					Gui.button({ caption: "Swap small", label: "Swap rows 2 and 99", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 98)) }),
					Gui.button({ caption: "Swap far", label: "Swap rows 2 and 9999", on_press: |value, _| Gui.Action.update(swap_rows(value, 1, 9998)) }),
					Gui.button({ caption: if state.compact "Show management" else "Show compact", label: "Toggle compact view", on_press: |value, _| Gui.Action.update({ ..value, compact: !value.compact }) }),
				],
			),
			Gui.text("Rows: ${state.order.len().to_str()}"),
			Gui.text("Selection: ${state.selected.to_str()}"),
			Gui.col({}, $rendered),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({ init: |_access| create_rows(0), render })
