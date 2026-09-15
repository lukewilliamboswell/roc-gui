## HTTP Workbench application wiring. Request state/transitions live in
## `Workbench.roc`; the mounted GUI description lives in `View.roc`.
app [State, main] { pf: platform "../../platform/main.roc", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst", roc: "nightly-2026-09-12-220fd47" }

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
