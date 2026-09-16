app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }
import pf.Program
import pf.Action
import pf.Component
import pf.Elem
import pf.Recipe
import Workspace

State : { primary : Workspace.State, secondary : Workspace.State, split : Bool }

workspace_get : State, Elem.Key -> Try(Workspace.State, [Removed])
workspace_get = |state, key| match Elem.Key.inspect(key) {
	Name("primary") => Ok(state.primary)
	Name("secondary") => if state.split Ok(state.secondary) else Err(Removed)
	_ => Err(Removed)
}

workspace_set : State, Elem.Key, Workspace.State -> Try(State, [Removed])
workspace_set = |state, key, workspace| match Elem.Key.inspect(key) {
	Name("primary") => Ok({ ..state, primary: workspace })
	Name("secondary") => if state.split Ok({ ..state, secondary: workspace }) else Err(Removed)
	_ => Err(Removed)
}

view : Recipe(State -> Elem(State))
view = Recipe.and_then(
	Workspace.view,
	|workspace_render|
		Recipe.map(
			Component.unmemoized({ get: workspace_get, set: workspace_set, render: workspace_render }),
			|workspace| |state| {
				primary = Elem.col({ label: "Primary workspace", width: Fill, height: Fill, grow: True }, [Elem.component(workspace, Name("primary"))])
				panes = if state.split [primary, Elem.col({ label: "Secondary workspace", width: Fill, height: Fill, grow: True }, [Elem.component(workspace, Name("secondary"))])] else [primary]
				Elem.col(
					{ width: Fill, height: Fill },
					[
						Elem.action_button({ caption: "Split workspace", label: "Split workspace", on_press: |latest, _| Action.update({ ..latest, split: True }) }),
						Elem.row(
							{ width: Fill, height: Fill, grow: True },
							panes,
						),
					],
				)
			},
		),
)

main = Program.build({
	init: { primary: Workspace.init, secondary: Workspace.init, split: False },
	render: view,
	window: { title: "Terminal Workspace", width: 900, height: 650 },
})
