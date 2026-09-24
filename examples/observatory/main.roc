app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui
import Observatory
import View

State : Observatory.State

main = Gui.run({
	init: Observatory.init,
	render: View.render,
	window: { title: "Observatory", width: 1440, height: 820 },
	on_open: Some(Observatory.opened!),
})
