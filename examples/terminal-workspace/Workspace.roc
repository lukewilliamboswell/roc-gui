import pf.Action
import pf.Elem
import Terminal
import Theme

Workspace := [].{
	State : State
	init : State
	init = { terminal: Terminal.init }
	render : State -> Elem.Elem(State)
	render = render
}

State : { terminal : Terminal.State }

divider = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.line, font_size: Theme.meta },
	[Elem.text(caption)],
)

meta = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta },
	[Elem.text(caption)],
)

header = Elem.row(
	Elem.RowProps.{
		label: "Workspace header",
		width: Fill,
		padding: Theme.inset,
		gap: 8,
		bg: Theme.region,
		border_color: Theme.line,
		border_width: 1,
		radius: Theme.radius,
		fg: Theme.text,
		font_size: Theme.meta,
	},
	[
		Elem.text("TERMINAL WORKSPACE"),
		divider("|"),
		meta("pty 100x30"),
		divider("|"),
		meta("utf-8"),
	],
)

render = |_state| Elem.col(
	Elem.ColProps.{
		label: "Terminal workspace",
		width: Fill,
		height: Fill,
		grow: True,
		padding: 8,
		gap: Theme.seam,
		bg: Theme.ground,
		fg: Theme.text,
		font_size: Theme.body,
	},
	[
		header,
		Elem.translate(Terminal.render, |current| current.terminal, |current, terminal| { ..current, terminal }),
	],
)
