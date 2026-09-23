app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }

import pf.Gui

Item : { id : U64, value : U64, command : [Idle, MoveFirst, RemoveSelf, StaleSet] }

State : { items : Gui.KeyedSeq(Item) }

render_item : Item -> Gui.Elem(Item)
render_item = |item| Gui.row(
	{ label: "Keyed item", gap: 8 },
	[
		Gui.text("item ${item.id.to_str()} value ${item.value.to_str()}"),
		Gui.button({ caption: "Increment ${item.id.to_str()}", label: "Increment ${item.id.to_str()}", on_press: |prev, _| Gui.Action.update({ ..prev, value: prev.value + 1 }) }),
		Gui.button({ caption: "Move ${item.id.to_str()} first", label: "Move ${item.id.to_str()} first", on_press: |prev, _| Gui.Action.delegate({ ..prev, command: MoveFirst }) }),
		Gui.button({ caption: "Task ${item.id.to_str()}", label: "Task ${item.id.to_str()}", on_press: |prev, _| Gui.Action.task({ pending: prev, run: || 10, resolve: |latest, amount| Gui.Action.update({ ..latest, value: latest.value + amount }) }) }),
		Gui.button({ caption: "Skip revision ${item.id.to_str()}", label: "Skip revision ${item.id.to_str()}", on_press: |prev, _| Gui.Action.delegate({ ..prev, command: StaleSet }) }),
		Gui.button({ caption: "Remove ${item.id.to_str()}", label: "Remove ${item.id.to_str()}", on_press: |prev, _| Gui.Action.delegate({ ..prev, command: RemoveSelf }) }),
	],
)

accept_command : State -> Gui.Action(State)
accept_command = |proposed| {
	var $next = proposed.items
	for entry in Gui.KeyedSeq.to_list(proposed.items) {
		match entry.value.command {
			Idle => {}
			MoveFirst => {
				reset = { ..entry.value, command: Idle }
				$next = Gui.KeyedSeq.set($next, entry.key, reset) ?? crash "reset moved keyed item"
				first = Gui.KeyedSeq.to_list($next).first() ?? crash "move in empty keyed column"
				$next = Gui.KeyedSeq.move_before($next, entry.key, Before(first.key)) ?? crash "move keyed item"
			}
			RemoveSelf => {
				$next = Gui.KeyedSeq.remove($next, entry.key) ?? crash "remove keyed item"
			}
			StaleSet => {
				intermediate = { ..entry.value, value: entry.value.value + 1, command: Idle }
				$next = Gui.KeyedSeq.set($next, entry.key, intermediate) ?? crash "first stale keyed set"
				$next = Gui.KeyedSeq.set($next, entry.key, { ..intermediate, value: intermediate.value + 1 }) ?? crash "second stale keyed set"
			}
		}
	}
	Gui.Action.update({ items: $next })
}

render : State -> Gui.Elem(State)
render = |_state| Gui.keyed_col(
	render_item,
	{ label: "Persistent keyed column", gap: 6, padding: 20 },
	{
		key: Gui.Key.from_str("items"),
		get: |state| state.items,
		set: |state, items| { ..state, items },
		on_delegate: |state, _key| accept_command(state),
	},
)

initial_items = Gui.KeyedSeq.from_list([
	{ key: Gui.Key.id(1), value: { id: 1, value: 0, command: Idle } },
	{ key: Gui.Key.id(2), value: { id: 2, value: 0, command: Idle } },
	{ key: Gui.Key.id(3), value: { id: 3, value: 0, command: Idle } },
]) ?? crash "initial keyed items"

main : Gui.Program(State)
main = Gui.run({
	init: |_access| { items: initial_items },
	render,
	window: { title: "Keyed column", width: 640, height: 480, background: 0xFFFFFF, foreground: 0x202020 },
})
