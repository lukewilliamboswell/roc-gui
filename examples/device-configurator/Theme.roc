## The configurator's visual vocabulary.
##
## This application's subject is a physical object on a desk, and the palette is
## chosen to suit one: graphite surfaces, and a single green that behaves like
## the link light on a piece of hardware. Green appears only where there is an
## open connection, amber only where there is a change the device has not been
## told about, and red only where something was refused or lost. A person can
## therefore answer "is it plugged in, and does it know about my edit?" from
## colour alone, before reading a word.
import pf.Action
import pf.Elem
import pf.Event
import pf.Gui

Theme := [].{
	ground = Gui.rgb(0x14181b)
	surface = Gui.rgb(0x1d2327)
	raised = Gui.rgb(0x262e34)
	hairline = Gui.rgb(0x38434a)

	ink = Gui.rgb(0xe6ebee)
	muted = Gui.rgb(0x8e9ba4)
	absent = Gui.rgb(0x5c6971)

	## Connected, and nothing else.
	link = Gui.rgb(0x6fc39a)
	link_tint = Gui.rgb(0x142620)
	link_deep = Gui.rgb(0x2f7a5b)
	on_link = Gui.rgb(0x07150f)

	## Held here, not on the device.
	pending = Gui.rgb(0xd9a760)
	pending_tint = Gui.rgb(0x2a2013)
	pending_deep = Gui.rgb(0x8a6428)

	## Refused, or lost.
	alarm = Gui.rgb(0xdd7f6d)
	alarm_tint = Gui.rgb(0x281b18)
	alarm_edge = Gui.rgb(0x5c3b34)

	caption : Str -> Elem.Elem(a)
	caption = |text| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: 11, font_weight: 700, fg: muted },
		[Elem.text(text)],
	)

	note : Str -> Elem.Elem(a)
	note = |text| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: 13, fg: muted },
		[Elem.text(text)],
	)

	## Quiet supporting text, for the line that explains why a control cannot be
	## pressed or what a number is bounded by.
	aside : Str -> Elem.Elem(a)
	aside = |text| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: 11, fg: absent },
		[Elem.text(text)],
	)

	## Anything that is a number or an identifier, in the fixed-pitch face.
	figure : Str, U32, Gui.Color -> Elem.Elem(a)
	figure = |text, size, colour| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: size, font_face: Monospace, fg: colour },
		[Elem.text(text)],
	)

	## The link light. It reports one fact -- whether a handle is open -- and it
	## is the fastest thing in the window to read.
	dot : Gui.Color -> Elem.Elem(a)
	dot = |colour| Elem.row(
		Elem.RowProps.{
			label: "Link indicator",
			width: Px(9),
			height: Px(9),
			min_width: Px(9),
			min_height: Px(9),
			padding: 0,
			gap: 0,
			radius: 5,
			bg: colour,
		},
		[],
	)

	## The primary control of a surface: one per surface, never two.
	primary : Str, Str, Bool, (a, Event.Press => Action.Action(a)) -> Elem.Elem(a)
	primary = |face, label, enabled, on_press| Elem.action_button(
		Elem.ActionButtonProps.{
			caption: face,
			label,
			enabled,
			on_press,
			height: Px(36),
			padding: 18,
			radius: 18,
			font_size: 14,
			font_weight: 600,
			bg: link,
			hover_bg: Gui.rgb(0x84d3ac),
			active_bg: link_deep,
			fg: on_link,
			disabled_bg: raised,
			disabled_fg: absent,
		},
	)

	## Everything else.
	secondary : Str, Str, Bool, (a, Event.Press => Action.Action(a)) -> Elem.Elem(a)
	secondary = |face, label, enabled, on_press| Elem.action_button(
		Elem.ActionButtonProps.{
			caption: face,
			label,
			enabled,
			on_press,
			height: Px(36),
			padding: 18,
			radius: 18,
			font_size: 14,
			font_weight: 600,
			bg: raised,
			hover_bg: Gui.rgb(0x303a41),
			active_bg: Gui.rgb(0x1e262b),
			fg: ink,
			border_color: hairline,
			border_width: 1,
			disabled_bg: surface,
			disabled_fg: absent,
		},
	)

	panel : Str, Gui.Length, List(Elem.Elem(a)) -> Elem.Elem(a)
	panel = |label, width, children| Elem.panel(
		Elem.PanelProps.{
			label,
			width,
			min_width: width,
			height: Fill,
			grow: True,
			padding: 16,
			gap: 12,
			radius: 12,
			overflow_y: Clip,
			bg: surface,
			border_color: hairline,
			fg: ink,
			font_size: 14,
		},
		children,
	)
}
