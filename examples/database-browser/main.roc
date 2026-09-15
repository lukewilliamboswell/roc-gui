app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Program
import Browser

State : Browser.State

main = Program.run({
	init: Browser.init,
	render: Browser.render,
	window: { title: "SQLite Database Browser", width: 1100, height: 760 },
})
