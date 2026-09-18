app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

State : { count : U64, search : Str }

settings = |count| {
	var $items = []
	for _ in List.repeat({}, count) {
		id = $items.len()
		category = if id % 4 == 0 {
			"Appearance"
		} else if id % 4 == 1 {
			"Editor"
		} else if id % 4 == 2 {
			"Privacy"
		} else {
			"Notifications"
		}
		$items = $items.append({ id, name: "Setting ${id.to_str()} — ${category}" })
	}
	$items
}

render = |state| {
	visible = settings(state.count).keep_if(|setting| state.search.is_empty() or setting.name.contains(state.search))
	Elem.col(
		Elem.ColProps.{ width: Fill, height: Fill, grow: True },
		[
			Elem.row(
				{},
				[
					Elem.button({ caption: "Load 100 settings", label: "Load 100 settings", on_press: |current, _| Action.update({ ..current, count: 100 }) }),
					Elem.button({ caption: "Load 1,000 settings", label: "Load 1000 settings", on_press: |current, _| Action.update({ ..current, count: 1000 }) }),
					Elem.button({ caption: "Load 10,000 settings", label: "Load 10000 settings", on_press: |current, _| Action.update({ ..current, count: 10000 }) }),
				],
			),
			Elem.text_input(Elem.TextInputProps.{ label: "Search settings", value: state.search, on_change: |current, event| Action.update({ ..current, search: event.value }), on_submit: |_, _| Action.none }),
			Elem.text("Matches: ${visible.len().to_str()}"),
			Elem.virtual_list(Elem.VirtualListProps.{ label: "Matching settings", row_height: 34, items: visible.map(|setting| Elem.VirtualListItem.{ key: setting.id, content: Elem.text(setting.name) }) }),
		],
	)
}

main : Program(State)
main = Program.run({ init: |_access| { count: 100, search: "" }, render })
