app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Component
import pf.Elem
import pf.Program
import pf.Recipe

Item : { value : I64, step : I64, archived : Bool }

Board : { item : Item, accepted : I64, present : Bool }

State : { board : Board, visible : Bool, shared : Bool, alternate : Bool }

initial : State
initial = { board: { item: { value: 0, step: 1, archived: False }, accepted: 0, present: True }, visible: True, shared: False, alternate: False }

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

render : Component(State), Component(State), Component(State), State -> Elem(State)
render = |board, alternate_board, shared_board, state| Elem.col(
	Elem.ColProps.{ label: "Review queue", gap: 12 },
	[
		button("Reset draft", |latest| Action.update({ ..latest, board: initial.board })),
		button("Double step", |latest| Action.update({ ..latest, board: { ..latest.board, item: { ..latest.board.item, step: 2 } } })),
		button("Refresh queue", |latest| Action.update(latest)),
		button("Toggle board", |latest| Action.update({ ..latest, visible: !latest.visible })),
		button("Share total", |latest| Action.update({ ..latest, shared: True })),
		button("Reopen board", |latest| Action.update({ ..latest, alternate: !latest.alternate })),
		if state.shared Elem.text("Shared draft ${state.board.item.value.to_str()}") else Elem.text("Private draft"),
		if state.visible Elem.component(if state.shared shared_board else if state.alternate alternate_board else board, Name("board")) else Elem.text("No board"),
	],
)

accept_or_archive : Board, Elem.Key -> Action(Board)
accept_or_archive = |candidate, _| if candidate.item.archived {
	Action.task({ pending: { ..candidate, present: False }, run: || 100.I64, resolve: |latest, result| Action.update({ ..latest, accepted: result }) })
} else if candidate.item.value <= 2 {
	Action.update({ ..candidate, accepted: candidate.item.value })
} else {
	Action.none
}

view : Recipe(State -> Elem(State))
view = Recipe.and_then(
	Component.define({
		get: item_get,
		set: item_set,
		render: item_render,
		on_delegate: accept_or_archive,
	}),
	|item| {
		private_board = Component.define({ get: board_get, set: board_set, render: |state| board_render(item, state) })
		Recipe.map(
			{
				private: private_board,
				alternate: private_board,
				shared: Component.memo({ get: board_get, set: board_set, render: |state| board_render(item, state), same: |previous, next| previous == next, update_scope: Parent }),
			}.Recipe,
			|boards| |state| render(boards.private, boards.alternate, boards.shared, state),
		)
	},
)

main : Program(State)
main = Program.build({
	init: initial,
	render: view,
	window: { title: "Review queue", width: 500, height: 500 },
})
