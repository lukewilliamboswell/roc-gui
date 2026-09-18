app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import pf.Action
import pf.Elem
import Workspace

State : { primary : Workspace.State, secondary : Workspace.State, split : Bool }

render : State -> Elem(State)
render = |state| {
	primary = Elem.col(
		{ label: "Primary workspace", width: Fill, height: Fill, grow: True },
		[
			Elem.translate_with(Workspace.render, { key: "primary", get: |parent| parent.primary, set: |parent, next| { ..parent, primary: next } }),
		],
	)
	panes = if state.split [
		primary,
		Elem.col(
			{ label: "Secondary workspace", width: Fill, height: Fill, grow: True },
			[
				Elem.try_translate(
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
	Elem.col(
		{ width: Fill, height: Fill },
		[
			Elem.action_button({ caption: "Split workspace", label: "Split workspace", on_press: |latest, _| Action.update({ ..latest, split: True }) }),
			Elem.row({ width: Fill, height: Fill, grow: True }, panes),
		],
	)
}

main = Program.run({
	init: |access| {
		start = Workspace.init
		{ primary: start(access), secondary: start(access), split: False }
	},
	render,
	window: { title: "Terminal Workspace", width: 900, height: 650 },
})
