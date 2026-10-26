app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

Page : { heading : Str, presses : U64 }

State : { page : Page }

render_page : Page -> Gui.Elem(Page)
render_page = |page| Gui.col(
	{ label: "Page", gap: 8, padding: 16 },
	[
		Gui.text(page.heading),
		Gui.text("Pressed ${page.presses.to_str()} times"),
		Gui.button({ caption: "Press", label: "Press", on_press: |current, _| Gui.Action.update({ ..current, presses: current.presses + 1 }) }),
	],
)

render : State -> Gui.Elem(State)
render = |_state| Gui.translate(render_page, |state| state.page, |state, page| { ..state, page })

main : Gui.Program(State)
main = Gui.run({
	init: |_access| { page: { heading: "Edit this file while the page runs", presses: 0 } },
	render,
	window: { title: "Hot reload", width: 480, height: 240 },
})
