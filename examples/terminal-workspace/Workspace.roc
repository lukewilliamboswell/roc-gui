import pf.Action
import pf.Program
import pf.Elem
import Terminal
import Theme

Workspace := [].{
	State : State
	## The pane's authority is the workspace's authority: a workspace owns one
	## terminal and hands it exactly what it was given.
	init : Program.Access -> State
	init = |access| {
		start = Terminal.init
		{ terminal: start(access) }
	}
	render : State -> Elem.Elem(State)
	render = render
}

State : { terminal : Terminal.State }

divider = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.line, font_size: Theme.meta },
	[Elem.text(caption)],
)

meta = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Elem.text(caption)],
)

## The last readout in an instrument header sits at the far edge, which is what
## a status field does. It grows into the space left over and justifies its own
## text to the end, so no spacer element exists only to push.
trailing_meta = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta },
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
		border_width: 0,
		border_bottom: Px(1),
		fg: Theme.text,
		font_size: Theme.meta,
	},
	[
		Elem.text("TERMINAL WORKSPACE"),
		divider("|"),
		meta("pty 100x30"),
		divider("|"),
		trailing_meta("utf-8"),
	],
)

render : State -> Elem.Elem(State)
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
		Elem.translate_with(Terminal.render, { key: "terminal", get: |state| state.terminal, set: |state, terminal| { ..state, terminal } }),
	],
)
