app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Key
import pf.KeyedSeq
import pf.Program

Item : { id : U64, value : U64, command : [Idle, MoveFirst, RemoveSelf, StaleSet] }

State : { items : KeyedSeq(Item) }

render_item : Item -> Elem(Item)
render_item = |item| Elem.row(
	Elem.RowProps.{ label: "Keyed item", gap: 8 },
	[
		Elem.text("item ${item.id.to_str()} value ${item.value.to_str()}"),
		Elem.button({ caption: "Increment ${item.id.to_str()}", label: "Increment ${item.id.to_str()}", on_press: |prev, _| Action.update({ ..prev, value: prev.value + 1 }) }),
		Elem.button({ caption: "Move ${item.id.to_str()} first", label: "Move ${item.id.to_str()} first", on_press: |prev, _| Action.delegate({ ..prev, command: MoveFirst }) }),
		Elem.button({ caption: "Task ${item.id.to_str()}", label: "Task ${item.id.to_str()}", on_press: |prev, _| Action.task({ pending: prev, run: || 10, resolve: |latest, amount| Action.update({ ..latest, value: latest.value + amount }) }) }),
		Elem.button({ caption: "Skip revision ${item.id.to_str()}", label: "Skip revision ${item.id.to_str()}", on_press: |prev, _| Action.delegate({ ..prev, command: StaleSet }) }),
		Elem.button({ caption: "Remove ${item.id.to_str()}", label: "Remove ${item.id.to_str()}", on_press: |prev, _| Action.delegate({ ..prev, command: RemoveSelf }) }),
	],
)

accept_command : State -> Action(State)
accept_command = |proposed| {
	var $next = proposed.items
	for entry in KeyedSeq.to_list(proposed.items) {
		match entry.value.command {
			Idle => {}
			MoveFirst => {
				reset = { ..entry.value, command: Idle }
				$next = KeyedSeq.set($next, entry.key, reset) ?? crash "reset moved keyed item"
				first = KeyedSeq.to_list($next).first() ?? crash "move in empty keyed column"
				$next = KeyedSeq.move_before($next, entry.key, Before(first.key)) ?? crash "move keyed item"
			}
			RemoveSelf => { $next = KeyedSeq.remove($next, entry.key) ?? crash "remove keyed item" }
			StaleSet => {
				intermediate = { ..entry.value, value: entry.value.value + 1, command: Idle }
				$next = KeyedSeq.set($next, entry.key, intermediate) ?? crash "first stale keyed set"
				$next = KeyedSeq.set($next, entry.key, { ..intermediate, value: intermediate.value + 1 }) ?? crash "second stale keyed set"
			}
		}
	}
	Action.update({ items: $next })
}

render : State -> Elem(State)
render = |_state| Elem.keyed_col(
	render_item,
	Elem.ColProps.{ label: "Persistent keyed column", gap: 6, padding: 20 },
	Elem.KeyedColConfig.{
		key: Key.from_str("items"),
		get: |state| state.items,
		set: |state, items| { ..state, items },
		on_delegate: |state, _key| accept_command(state),
	},
)

initial_items = KeyedSeq.from_list([
	{ key: Key.id(1), value: { id: 1, value: 0, command: Idle } },
	{ key: Key.id(2), value: { id: 2, value: 0, command: Idle } },
	{ key: Key.id(3), value: { id: 3, value: 0, command: Idle } },
]) ?? crash "initial keyed items"

main : Program(State)
main = Program.run({
	init: { items: initial_items },
	render,
	window: { title: "Keyed column", width: 640, height: 480, background: Gui.rgb(0xFFFFFF), foreground: Gui.rgb(0x202020) },
})
