## Settings Center application wiring.
##
## - State and preference operations: `Settings.roc`
## - Presentation and control routes: `Render.roc`
## - Behaviour and scaling specifications: `specs/`
app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Program
import Render
import Settings

State : Settings.State

main : Program(State)
main = Program.run({
	init: Settings.initial,
	render: Render.render,
	window: { title: "Settings Center", width: 1040, height: 760 },
})
