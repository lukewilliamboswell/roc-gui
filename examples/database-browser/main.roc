app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Gui
import Browser
import View

State : Browser.State

main = Gui.run({
	init: Browser.init,
	render: View.render,
	window: { title: "SQLite Database Browser", width: 1100, height: 760 },
})
