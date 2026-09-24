app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

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
	Gui.col(
		{ width: Fill, height: Fill, grow: True },
		[
			Gui.row(
				{},
				[
					Gui.button({ caption: "Load 100 settings", label: "Load 100 settings", on_press: |current, _| Gui.update({ ..current, count: 100 }) }),
					Gui.button({ caption: "Load 1,000 settings", label: "Load 1000 settings", on_press: |current, _| Gui.update({ ..current, count: 1000 }) }),
					Gui.button({ caption: "Load 10,000 settings", label: "Load 10000 settings", on_press: |current, _| Gui.update({ ..current, count: 10000 }) }),
				],
			),
			Gui.text_input({ label: "Search settings", value: state.search, on_change: |current, event| Gui.update({ ..current, search: event.value }), on_submit: |_, _| Gui.none }),
			Gui.text("Matches: ${visible.len().to_str()}"),
			Gui.virtual_list({ label: "Matching settings", row_height: 34, items: visible.map(|setting| { key: setting.id, content: Gui.text(setting.name) }) }),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({ init: |_access| { count: 100, search: "" }, render })
