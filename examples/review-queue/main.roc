app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

Item : { value : I64, step : I64, archived : Bool, shared : Bool }

Board : { item : Item, accepted : I64, present : Bool, writable : Bool }

State : { board : Board, visible : Bool, shared : Bool, alternate : Bool, memoized : Bool, unkeyed : Bool }

initial : State
initial = { board: { item: { value: 0, step: 1, archived: False, shared: False }, accepted: 0, present: True, writable: True }, visible: True, shared: False, alternate: False, memoized: True, unkeyed: False }

button = |name, action| Gui.button({ caption: name, label: name, on_press: |state, _| action(state) })

item_render : Item -> Gui.Elem(Item)
item_render = |item| Gui.col(
	{ label: "Review item" },
	[
		Gui.text("Draft ${item.value.to_str()}"),
		button("Edit draft", |latest| if latest.shared Gui.delegate({ ..latest, value: latest.value + item.step }) else Gui.update({ ..latest, value: latest.value + item.step })),
		button("Revise draft", |latest| Gui.delegate({ ..latest, value: -1 })),
		button("Propose rejected draft", |latest| Gui.delegate({ ..latest, value: 99 })),
		button("Accept draft", |latest| Gui.delegate(latest)),
		button("Archive draft", |latest| Gui.delegate({ ..latest, archived: True })),
		button("Enrich draft", |latest| Gui.task({ pending: latest, run: || 10.I64, resolve: |current, result| if current.shared Gui.delegate({ ..current, value: current.value + result }) else Gui.update({ ..current, value: current.value + result }) })),
	],
)

item_get : Board -> Try(Item, [Removed])
item_get = |board| if board.present Ok(board.item) else Err(Removed)

item_set : Board, Item -> Try(Board, [Removed])
item_set = |board, item| if board.present and board.writable Ok({ ..board, item }) else Err(Removed)

board_get : State -> Try(Board, [Removed])
board_get = |state| if state.visible Ok(state.board) else Err(Removed)

board_set : State, Board -> Try(State, [Removed])
board_set = |state, board| if state.visible Ok({ ..state, board }) else Err(Removed)

board_render : Board -> Gui.Elem(Board)
board_render = |board| Gui.col(
	{ label: "Review board" },
	[
		Gui.text("Accepted ${board.accepted.to_str()}"),
		if board.present Gui.try_translate(item_render, { key: "draft", get: item_get, set: item_set, on_delegate: accept_or_archive, memo: Some(|previous, next| previous == next) }) else Gui.text("Archived"),
	],
)

render : State -> Gui.Elem(State)
render = |state| Gui.col(
	{ label: "Review queue", gap: 12 },
	[
		button("Lock draft", |latest| Gui.update({ ..latest, board: { ..latest.board, writable: False } })),
		button("Unlock draft", |latest| Gui.update({ ..latest, board: { ..latest.board, writable: True } })),
		button("Disable board memo", |latest| Gui.update({ ..latest, memoized: False })),
		button("Enable board memo", |latest| Gui.update({ ..latest, memoized: True })),
		button("Use unkeyed board", |latest| Gui.update({ ..latest, unkeyed: True })),
		button("Reset draft", |latest| Gui.update({ ..latest, board: initial.board })),
		button("Double step", |latest| Gui.update({ ..latest, board: { ..latest.board, item: { ..latest.board.item, step: 2 } } })),
		button("Refresh queue", |latest| Gui.update(latest)),
		button("Toggle board", |latest| Gui.update({ ..latest, visible: !latest.visible })),
		button("Share total", |latest| Gui.update({ ..latest, shared: True, board: { ..latest.board, item: { ..latest.board.item, shared: True } } })),
		button("Reopen board", |latest| Gui.update({ ..latest, alternate: !latest.alternate })),
		if state.shared Gui.text("Shared draft ${state.board.item.value.to_str()}") else Gui.text("Private draft"),
		if !state.visible Gui.text("No board") else if state.unkeyed Gui.translate(board_render, |parent| parent.board, |parent, board| { ..parent, board }) else Gui.try_translate(board_render, { key: if state.alternate "alternate-board" else "board", get: board_get, set: board_set, memo: if state.memoized Some(|previous, next| previous == next) else None }),
	],
)

accept_or_archive : Board -> Gui.Action(Board)
accept_or_archive = |candidate| if candidate.item.archived {
	Gui.task({ pending: { ..candidate, present: False }, run: || 100.I64, resolve: |latest, result| Gui.update({ ..latest, accepted: result }) })
} else if candidate.item.shared {
	Gui.delegate(candidate)
} else if candidate.item.value < 0 {
	Gui.update({ ..candidate, item: { ..candidate.item, value: 0 }, accepted: 0 })
} else if candidate.item.value <= 2 {
	Gui.update({ ..candidate, accepted: candidate.item.value })
} else {
	Gui.none
}

main : Gui.Program(State)
main = Gui.run({
	init: |_access| initial,
	render,
	window: { title: "Review queue", width: 500, height: 500 },
})
