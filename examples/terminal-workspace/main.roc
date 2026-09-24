app [State, main] { pf: platform "../../platform/main.roc" }
import pf.Gui
import Workspace

## The divider between the two workspaces: how wide the secondary one is, in
## logical pixels, and whether it is folded away.
Divider : { size : U32, collapsed : Bool }

State : { primary : Workspace.State, secondary : Workspace.State, split : Bool, divider : Divider }

render : State -> Gui.Elem(State)
render = |state| {
	primary = Gui.col(
		{ label: "Primary workspace", width: Fill, height: Fill, grow: True },
		[
			Gui.translate_with(Workspace.render, { key: "primary", get: |parent| parent.primary, set: |parent, next| { ..parent, primary: next } }),
		],
	)
	# The secondary workspace mounts the first time the workspace splits, and
	# stays mounted while the divider folds it away. Until then its place is
	# empty and folded, so splitting never moves the primary workspace.
	secondary = if state.split {
		Gui.col(
			{ label: "Secondary workspace", width: Fill, height: Fill, grow: True },
			[
				Gui.try_translate(
					Workspace.render,
					{
						key: "secondary",
						get: |parent| if parent.split Ok(parent.secondary) else Err(Removed),
						set: |parent, next| if parent.split Ok({ ..parent, secondary: next }) else Err(Removed),
					},
				),
			],
		)
	} else {
		Gui.col({ width: Fill, height: Fill }, [])
	}
	panes = Gui.split(
		{
			label: "Workspace divider",
			side: End,
			size: state.divider.size,
			min: 240,
			max: 720,
			collapsible: True,
			collapsed: !state.split or state.divider.collapsed,
			on_resize: |latest, event| Gui.update({ ..latest, split: latest.split or !event.collapsed, divider: event }),
		},
		primary,
		secondary,
	)
	Gui.col(
		{ width: Fill, height: Fill },
		[
			Gui.button({ caption: "Split workspace", label: "Split workspace", on_press: |latest, _| Gui.update({ ..latest, split: True, divider: { ..latest.divider, collapsed: False } }) }),
			Gui.row({ width: Fill, height: Fill, grow: True }, [panes]),
		],
	)
}

main = Gui.run({
	init: |access| {
		start = Workspace.init
		{ primary: start(access), secondary: start(access), split: False, divider: { size: 440, collapsed: False } }
	},
	render,
	window: { title: "Terminal Workspace", width: 900, height: 650 },
})
