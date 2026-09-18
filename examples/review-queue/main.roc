app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

Item : { value : I64, step : I64, archived : Bool, shared : Bool }

Board : { item : Item, accepted : I64, present : Bool, writable : Bool }

State : { board : Board, visible : Bool, shared : Bool, alternate : Bool, memoized : Bool, unkeyed : Bool }

initial : State
initial = { board: { item: { value: 0, step: 1, archived: False, shared: False }, accepted: 0, present: True, writable: True }, visible: True, shared: False, alternate: False, memoized: True, unkeyed: False }

button = |name, action| Elem.action_button(Elem.ActionButtonProps.{ caption: name, label: name, on_press: |state, _| action(state) })

item_render : Item -> Elem(Item)
item_render = |item| Elem.col(
	Elem.ColProps.{ label: "Review item" },
	[
		Elem.text("Draft ${item.value.to_str()}"),
		button("Edit draft", |latest| if latest.shared Action.delegate({ ..latest, value: latest.value + item.step }) else Action.update({ ..latest, value: latest.value + item.step })),
		button("Revise draft", |latest| Action.delegate({ ..latest, value: -1 })),
		button("Propose rejected draft", |latest| Action.delegate({ ..latest, value: 99 })),
		button("Accept draft", |latest| Action.delegate(latest)),
		button("Archive draft", |latest| Action.delegate({ ..latest, archived: True })),
		button("Enrich draft", |latest| Action.task({ pending: latest, run: || 10.I64, resolve: |current, result| if current.shared Action.delegate({ ..current, value: current.value + result }) else Action.update({ ..current, value: current.value + result }) })),
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

board_render : Board -> Elem(Board)
board_render = |board| Elem.col(
	Elem.ColProps.{ label: "Review board" },
	[
		Elem.text("Accepted ${board.accepted.to_str()}"),
		if board.present Elem.try_translate(item_render, { key: "draft", get: item_get, set: item_set, on_delegate: accept_or_archive, memo: Some(|previous, next| previous == next) }) else Elem.text("Archived"),
	],
)

render : State -> Elem(State)
render = |state| Elem.col(
	Elem.ColProps.{ label: "Review queue", gap: 12 },
	[
		button("Lock draft", |latest| Action.update({ ..latest, board: { ..latest.board, writable: False } })),
		button("Unlock draft", |latest| Action.update({ ..latest, board: { ..latest.board, writable: True } })),
		button("Disable board memo", |latest| Action.update({ ..latest, memoized: False })),
		button("Enable board memo", |latest| Action.update({ ..latest, memoized: True })),
		button("Use unkeyed board", |latest| Action.update({ ..latest, unkeyed: True })),
		button("Reset draft", |latest| Action.update({ ..latest, board: initial.board })),
		button("Double step", |latest| Action.update({ ..latest, board: { ..latest.board, item: { ..latest.board.item, step: 2 } } })),
		button("Refresh queue", |latest| Action.update(latest)),
		button("Toggle board", |latest| Action.update({ ..latest, visible: !latest.visible })),
		button("Share total", |latest| Action.update({ ..latest, shared: True, board: { ..latest.board, item: { ..latest.board.item, shared: True } } })),
		button("Reopen board", |latest| Action.update({ ..latest, alternate: !latest.alternate })),
		if state.shared Elem.text("Shared draft ${state.board.item.value.to_str()}") else Elem.text("Private draft"),
		if !state.visible Elem.text("No board") else if state.unkeyed Elem.translate(board_render, |parent| parent.board, |parent, board| { ..parent, board }) else Elem.try_translate(board_render, { key: if state.alternate "alternate-board" else "board", get: board_get, set: board_set, memo: if state.memoized Some(|previous, next| previous == next) else None }),
	],
)

accept_or_archive : Board -> Action(Board)
accept_or_archive = |candidate| if candidate.item.archived {
	Action.task({ pending: { ..candidate, present: False }, run: || 100.I64, resolve: |latest, result| Action.update({ ..latest, accepted: result }) })
} else if candidate.item.shared {
	Action.delegate(candidate)
} else if candidate.item.value < 0 {
	Action.update({ ..candidate, item: { ..candidate.item, value: 0 }, accepted: 0 })
} else if candidate.item.value <= 2 {
	Action.update({ ..candidate, accepted: candidate.item.value })
} else {
	Action.none
}

main : Program(State)
main = Program.run({
	init: initial,
	render,
	window: { title: "Review queue", width: 500, height: 500 },
})
