## HTTP Workbench application wiring. Request state/transitions live in
## `Workbench.roc`; the mounted GUI description lives in `View.roc`.
app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Program exposing [Program]
import View
import Workbench

State : Workbench.State

main : Program(State)
main = Program.run({
	init: Workbench.init,
	render: View.render,
	window: { title: "HTTP Workbench", width: 840, height: 680 },
})
