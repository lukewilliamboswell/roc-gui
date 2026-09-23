app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Explorer
State : Explorer.State

## The window declares the ground the explorer's surfaces are mixed against
## rather than inheriting the host's, so the identity cannot be pulled out from
## under the application by a change it does not control.
main = Gui.run({
	init: Explorer.init,
	render: Explorer.render,
	window: {
		title: "File Explorer",
		width: 960,
		height: 640,
		background: Explorer.ground,
		foreground: Explorer.ink,
	},
})
