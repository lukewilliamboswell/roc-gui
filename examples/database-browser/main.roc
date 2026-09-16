app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-15-fe09c42" }

import pf.Program
import Browser
import View

State : Browser.State

main = Program.run({
	init: Browser.init,
	render: View.render,
	window: { title: "SQLite Database Browser", width: 1100, height: 760 },
})
