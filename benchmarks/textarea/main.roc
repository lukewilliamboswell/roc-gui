app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Component
import pf.Elem
import pf.Program
import pf.Recipe

State : { body : Str, memoized : Bool, loaded : Bool }

payload = |size| Str.join_with(List.repeat("x", size), "")

editor : Str -> Elem(Str)
editor = |body| Elem.col(
	{},
	[
		Elem.textarea(Elem.TextareaProps.{ label: "Large request body", value: body, on_input: |_, event| Action.update(event.value), height: Fill, grow: True }),
		Elem.button({ caption: "Append byte", label: "Append byte", on_press: |latest, _| Action.update(latest.concat("x")) }),
	],
)

get_body : State, Elem.Key -> Try(Str, [Removed])
get_body = |state, _| Ok(state.body)

set_body : State, Elem.Key, Str -> Try(State, [Removed])
set_body = |state, _, body| Ok({ ..state, body })

render : Component(State), Component(State), State -> Elem(State)
render = |memoized, unmemoized, state| Elem.col(
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
		if state.loaded Elem.component(if state.memoized memoized else unmemoized, Name("body")) else Elem.text("Load a request body"),
	],
)

main : Program(State)
main = Program.build({
	init: { body: "", memoized: True, loaded: False },
	render: Recipe.map(
		{
			memoized: Component.define({ get: get_body, set: set_body, render: editor }),
			unmemoized: Component.unmemoized({ get: get_body, set: set_body, render: editor }),
		}.Recipe,
		|definitions| |state| render(definitions.memoized, definitions.unmemoized, state),
	),
	window: { title: "Textarea benchmark", width: 900, height: 650 },
})
