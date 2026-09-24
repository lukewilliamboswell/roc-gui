app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

State : { body : Str, memoized : Bool, loaded : Bool }

payload = |size| Str.join_with(List.repeat("x", size), "")

## Replace the final Unicode scalar while preserving the preceding text.
edit_last : Str -> Str
edit_last = |body| {
	bytes = body.to_utf8()
	if bytes.is_empty() {
		return body
	}
	var $cut = bytes.len() - 1
	while $cut > 0 and (bytes.get($cut) ?? 0) >= 0x80 and (bytes.get($cut) ?? 0) < 0xC0 {
		$cut = $cut - 1
	}
	prefix = Str.from_utf8(bytes.take_first($cut)) ?? crash "invalid UTF-8 prefix"
	prefix.concat("y")
}

editor : Str -> Gui.Elem(Str)
editor = |body| Gui.col(
	{},
	[
		Gui.textarea({ label: "Large request body", value: body, on_input: |_, event| Gui.update(event.value), height: Fill, grow: True }),
		Gui.button({ caption: "Edit last byte", label: "Edit last byte", on_press: |latest, _| Gui.update(edit_last(latest)) }),
		Gui.button({ caption: "Append byte", label: "Append byte", on_press: |latest, _| Gui.update(latest.concat("x")) }),
	],
)

render : State -> Gui.Elem(State)
render = |state| Gui.col(
	{ width: Fill, height: Fill, grow: True, padding: 16 },
	[
		Gui.row(
			{},
			[
				Gui.button({ caption: "Load 100 bytes", label: "Load 100 bytes", on_press: |latest, _| Gui.update({ ..latest, body: payload(100), loaded: True }) }),
				Gui.button({ caption: "Load 1,000 bytes", label: "Load 1000 bytes", on_press: |latest, _| Gui.update({ ..latest, body: payload(1000), loaded: True }) }),
				Gui.button({ caption: "Load 10,000 bytes", label: "Load 10000 bytes", on_press: |latest, _| Gui.update({ ..latest, body: payload(10000), loaded: True }) }),
				Gui.button({ caption: "Load 100,000 bytes", label: "Load 100000 bytes", on_press: |latest, _| Gui.update({ ..latest, body: payload(100000), loaded: True }) }),
				Gui.button({ caption: "Memoized", label: "Use memoized editor", on_press: |latest, _| Gui.update({ ..latest, memoized: True }) }),
				Gui.button({ caption: "Unmemoized", label: "Use unmemoized editor", on_press: |latest, _| Gui.update({ ..latest, memoized: False }) }),
				Gui.button({ caption: "Refresh", label: "Refresh editor", on_press: |latest, _| Gui.update(latest) }),
			],
		),
		if state.loaded Gui.translate_with(editor, { key: "body", get: |parent| parent.body, set: |parent, body| { ..parent, body }, memo: if state.memoized Some(|previous, next| previous == next) else None }) else Gui.text("Load a request body"),
	],
)

main : Gui.Program(State)
main = Gui.run({
	init: |_access| { body: "", memoized: True, loaded: False },
	render,
	window: { title: "Textarea benchmark", width: 900, height: 650 },
})
