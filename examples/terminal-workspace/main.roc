app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-22-e494788" }
import pf.Gui
import Workspace

State : { primary : Workspace.State, secondary : Workspace.State, split : Bool }

render : State -> Gui.Elem(State)
render = |state| {
	primary = Gui.col(
		{ label: "Primary workspace", width: Fill, height: Fill, grow: True },
		[
			Gui.translate_with(Workspace.render, { key: "primary", get: |parent| parent.primary, set: |parent, next| { ..parent, primary: next } }),
		],
	)
	panes = if state.split [
		primary,
		Gui.col(
			{ label: "Secondary workspace", width: Fill, height: Fill, grow: True },
			[
				Gui.try_translate(
					Workspace.render,
					{
						key: "secondary",
						get: |parent| if parent.split Ok(parent.secondary) else Err(Removed),
						set: |parent, secondary| if parent.split Ok({ ..parent, secondary }) else Err(Removed),
					},
				),
			],
		),
	] else [primary]
	Gui.col(
		{ width: Fill, height: Fill },
		[
			Gui.button({ caption: "Split workspace", label: "Split workspace", on_press: |latest, _| Gui.Action.update({ ..latest, split: True }) }),
			Gui.row({ width: Fill, height: Fill, grow: True }, panes),
		],
	)
}

main = Gui.run({
	init: |access| {
		start = Workspace.init
		{ primary: start(access), secondary: start(access), split: False }
	},
	render,
	window: { title: "Terminal Workspace", width: 900, height: 650 },
})
