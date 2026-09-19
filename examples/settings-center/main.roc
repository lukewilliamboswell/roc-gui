## Settings Center application wiring.
##
## - State and preference operations: `Settings.roc`
## - Presentation and control routes: `Render.roc`
## - Behaviour and scaling specifications: `specs/`
app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Gui
import Render
import Settings

State : Settings.State

main : Gui.Program(State)
main = Gui.run({
	init: Settings.initial,
	render: Render.render,
	window: { title: "Settings Center", width: 1040, height: 760 },
})
