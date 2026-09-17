app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

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

editor : Str -> Elem(Str)
editor = |body| Elem.col(
	{},
	[
		Elem.textarea(Elem.TextareaProps.{ label: "Large request body", value: body, on_input: |_, event| Action.update(event.value), height: Fill, grow: True }),
		Elem.button({ caption: "Edit last byte", label: "Edit last byte", on_press: |latest, _| Action.update(edit_last(latest)) }),
		Elem.button({ caption: "Append byte", label: "Append byte", on_press: |latest, _| Action.update(latest.concat("x")) }),
	],
)

render : State -> Elem(State)
render = |state| Elem.col(
	Elem.ColProps.{ width: Fill, height: Fill, grow: True, padding: 16 },
	[
		Elem.row(
			{},
			[
				Elem.button({ caption: "Load 100 bytes", label: "Load 100 bytes", on_press: |latest, _| Action.update({ ..latest, body: payload(100), loaded: True }) }),
				Elem.button({ caption: "Load 1,000 bytes", label: "Load 1000 bytes", on_press: |latest, _| Action.update({ ..latest, body: payload(1000), loaded: True }) }),
				Elem.button({ caption: "Load 10,000 bytes", label: "Load 10000 bytes", on_press: |latest, _| Action.update({ ..latest, body: payload(10000), loaded: True }) }),
				Elem.button({ caption: "Load 100,000 bytes", label: "Load 100000 bytes", on_press: |latest, _| Action.update({ ..latest, body: payload(100000), loaded: True }) }),
				Elem.button({ caption: "Memoized", label: "Use memoized editor", on_press: |latest, _| Action.update({ ..latest, memoized: True }) }),
				Elem.button({ caption: "Unmemoized", label: "Use unmemoized editor", on_press: |latest, _| Action.update({ ..latest, memoized: False }) }),
				Elem.button({ caption: "Refresh", label: "Refresh editor", on_press: |latest, _| Action.update(latest) }),
			],
		),
		if state.loaded Elem.translate_with(editor, { key: "body", get: |parent| parent.body, set: |parent, body| { ..parent, body }, memo: if state.memoized Some(|previous, next| previous == next) else None }) else Elem.text("Load a request body"),
	],
)

main : Program(State)
main = Program.run({
	init: { body: "", memoized: True, loaded: False },
	render,
	window: { title: "Textarea benchmark", width: 900, height: 650 },
})
