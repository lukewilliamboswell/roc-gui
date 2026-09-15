import pf.Action
import pf.Elem
import pf.Gui
import Terminal

Workspace := [].{
	State : State
	init : State
	init = { terminal: Terminal.init }
	render : State -> Elem.Elem(State)
	render = render
}

State : { terminal : Terminal.State }

render = |_state| Elem.col(
	Elem.ColProps.{ label: "Terminal workspace", width: Fill, height: Fill, grow: True, padding: 20, gap: 16, bg: Gui.rgb(0x10181d) },
	[
		Elem.text("Terminal Workspace"),
		Elem.translate(Terminal.render, |current| current.terminal, |current, terminal| { ..current, terminal }),
	],
)
