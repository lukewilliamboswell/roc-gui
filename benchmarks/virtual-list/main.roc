app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Gui

## The list either holds every row as an item, or holds a row count and builds
## rows on demand. Both are the production list; the second is what an
## application whose rows are data it has not loaded yet would use.
State : { rows : List(U64), provided : U64, on_demand : Bool, selected : U64, jump : [None, Some(Gui.ScrollRequest)] }

make_rows = |count| {
	var $rows = []
	for _ in List.repeat({}, count) {
		$rows = $rows.append($rows.len())
	}
	$rows
}

row_button : U64 -> Gui.Elem(State)
row_button = |row| Gui.button({ caption: "Virtual row ${row.to_str()}", label: "Select virtual row ${row.to_str()}", on_press: |current, _| Gui.update({ ..current, selected: row }) })

load = |count| Gui.button({ caption: "Load ${count.to_str()} rows", label: "Load ${count.to_str()} rows", on_press: |_, _| Gui.update({ rows: make_rows(count), provided: 0, on_demand: False, selected: count, jump: None }) })

provide = |count| Gui.button({ caption: "Provide ${count.to_str()} rows", label: "Provide ${count.to_str()} rows", on_press: |_, _| Gui.update({ rows: [], provided: count, on_demand: True, selected: count, jump: None }) })

rows_list = |state| if state.on_demand {
	Gui.virtual_rows({ label: "Rows", row_height: 28, count: state.provided, render_row: row_button, scroll_to: state.jump })
} else {
	Gui.virtual_list({ label: "Rows", row_height: 28, items: state.rows.map(|row| { key: row, content: row_button(row) }) })
}

## How many rows the list holds, whichever way it holds them.
total : State -> U64
total = |state| if state.on_demand state.provided else state.rows.len()

## Select a row and, for rows produced on demand, bring it into view. A new
## serial moves the list even to the row it last moved to.
select : State, U64 -> Gui.Action(State)
select = |state, row| {
	serial = match state.jump {
		None => 0
		Some(previous) => previous.serial + 1
	}
	jump = if state.on_demand Some({ row, align: Nearest, serial }) else state.jump
	Gui.update({ ..state, selected: row, jump })
}

## The keyboard moves the selection one row, or to either end, wherever focus
## is. Nothing is selected until the first move, which starts at the end it
## moves from.
step : State, [Next, Previous, First, Last] -> Gui.Action(State)
step = |state, move| {
	count = total(state)
	chosen = state.selected < count
	if count == 0 {
		Gui.none
	} else {
		row = match move {
			Next => if !chosen 0 else if state.selected + 1 < count state.selected + 1 else state.selected
			Previous => if !chosen count - 1 else if state.selected > 0 state.selected - 1 else 0
			First => 0
			Last => count - 1
		}
		select(state, row)
	}
}

navigation : List(Gui.Shortcut(State))
navigation = [
	{ keys: "down", on_press: |current, _| step(current, Next) },
	{ keys: "up", on_press: |current, _| step(current, Previous) },
	{ keys: "home", on_press: |current, _| step(current, First) },
	{ keys: "end", on_press: |current, _| step(current, Last) },
]

render = |state| Gui.col(
	{ width: Fill, height: Fill, grow: True },
	[
		Gui.row({}, [load(100), load(1000), load(10000)]),
		Gui.row(
			{},
			[
				provide(10000),
				provide(100000),
				provide(1000000),
				Gui.button({
					caption: "Jump to last row",
					label: "Jump to last row",
					on_press: |current, _| if current.on_demand and current.provided > 0 {
						serial = match current.jump {
							None => 0
							Some(previous) => previous.serial + 1
						}
						Gui.update({ ..current, jump: Some({ row: current.provided - 1, align: End, serial }) })
					} else {
						Gui.none
					},
				}),
			],
		),
		Gui.text("Rows: ${total(state).to_str()}"),
		Gui.text("Selected: ${state.selected.to_str()}"),
		rows_list(state),
	],
).shortcuts(navigation)

main : Gui.Program(State)
main = Gui.run({ init: |_access| { rows: [], provided: 0, on_demand: False, selected: 0, jump: None }, render })
