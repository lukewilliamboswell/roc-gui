app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Gui
import Browser
State : Browser.State

## The window declares the ground its identity is drawn on rather than
## inheriting one: every surface in `Browser.roc` is mixed against this
## deep teal, and a host that changed its own default would otherwise pull
## the whole palette out from under them.
main = Gui.run({
	init: Browser.init,
	render: Browser.render,
	window: {
		title: "Folder browser",
		width: 760,
		height: 560,
		background: Browser.ground,
		foreground: Browser.ink,
	},
})
