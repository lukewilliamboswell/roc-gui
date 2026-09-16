app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Component
import pf.Elem
import pf.Program

Item : { value : I64, step : I64, archived : Bool }

Board : { item : Item, accepted : I64, present : Bool }

State : { board : Board, visible : Bool, shared : Bool }

initial : State
initial = { board: { item: { value: 0, step: 1, archived: False }, accepted: 0, present: True }, visible: True, shared: False }

button = |name, action| Elem.action_button(Elem.ActionButtonProps.{ caption: name, label: name, on_press: |state, _| action(state) })

item_render : Item -> Elem(Item)
item_render = |item| Elem.col(
	Elem.ColProps.{ label: "Review item" },
	[
		Elem.text("Draft ${item.value.to_str()}"),
		button("Edit draft", |latest| Action.update({ ..latest, value: latest.value + item.step })),
		button("Accept draft", |latest| Action.delegate(latest)),
		button("Archive draft", |latest| Action.delegate({ ..latest, archived: True })),
		button("Enrich draft", |latest| Action.task({ pending: latest, run: || 10.I64, resolve: |current, result| Action.update({ ..current, value: current.value + result }) })),
	],
)

item_get : Board, Elem.Key -> Try(Item, [Removed])
item_get = |board, _| if board.present Ok(board.item) else Err(Removed)

item_set : Board, Elem.Key, Item -> Try(Board, [Removed])
item_set = |board, _, item| if board.present Ok({ ..board, item }) else Err(Removed)

board_get : State, Elem.Key -> Try(Board, [Removed])
board_get = |state, _| if state.visible Ok(state.board) else Err(Removed)

board_set : State, Elem.Key, Board -> Try(State, [Removed])
board_set = |state, _, board| if state.visible Ok({ ..state, board }) else Err(Removed)

board_render : Component(Board), Board -> Elem(Board)
board_render = |item, board| Elem.col(
	Elem.ColProps.{ label: "Review board" },
	[
		Elem.text("Accepted ${board.accepted.to_str()}"),
		if board.present Elem.component(item, Name("draft")) else Elem.text("Archived"),
	],
)

render : Component(State), Component(State), State -> Elem(State)
render = |board, shared_board, state| Elem.col(
	Elem.ColProps.{ label: "Review queue", gap: 12 },
	[
		button("Reset draft", |latest| Action.update({ ..latest, board: initial.board })),
		button("Double step", |latest| Action.update({ ..latest, board: { ..latest.board, item: { ..latest.board.item, step: 2 } } })),
		button("Refresh queue", |latest| Action.update(latest)),
		button("Toggle board", |latest| Action.update({ ..latest, visible: !latest.visible })),
		button("Share total", |latest| Action.update({ ..latest, shared: True })),
		if state.shared Elem.text("Shared draft ${state.board.item.value.to_str()}") else Elem.text("Private draft"),
		if state.visible Elem.component(if state.shared shared_board else board, Name("board")) else Elem.text("No board"),
	],
)

setup! : () => { state : State, render : State -> Elem(State) }
setup! = || {
	item : Component(Board)
	item = Component.define!({
		get: item_get,
		set: item_set,
		render: item_render,
		on_delegate: |candidate, _| if candidate.item.archived Action.task({ pending: { ..candidate, present: False }, run: || 100.I64, resolve: |latest, result| Action.update({ ..latest, accepted: result }) }) else if candidate.item.value <= 2 Action.update({ ..candidate, accepted: candidate.item.value }) else Action.none,
	})
	board : Component(State)
	board = Component.define!({
		get: board_get,
		set: board_set,
		render: |state| board_render(item, state),
	})
	shared_board : Component(State)
	# This variant exercises the explicit comparator override. Its equivalence
	# includes the complete board, including the step captured by item handlers.
	shared_board = Component.memo!({ get: board_get, set: board_set, render: |state| board_render(item, state), same: |previous, next| previous == next, update_scope: Parent })
	{ state: initial, render: |state| render(board, shared_board, state) }
}

main : Program(State)
main = Program.run({ setup: setup!, window: { title: "Review queue", width: 500, height: 500 } })
