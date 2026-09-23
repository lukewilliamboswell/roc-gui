app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Gui
import Observatory
import View

State : Observatory.State

main = Gui.run({
	init: Observatory.init,
	render: View.render,
	window: { title: "Observatory", width: 1280, height: 820 },
})
