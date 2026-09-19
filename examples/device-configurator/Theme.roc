## The configurator's visual vocabulary.
##
## This application's subject is a physical object on a desk, and the palette is
## chosen to suit one: graphite surfaces, and a single green that behaves like
## the link light on a piece of hardware. Green appears only where there is an
## open connection, amber only where there is a change the device has not been
## told about, and red only where something was refused or lost. A person can
## therefore answer "is it plugged in, and does it know about my edit?" from
## colour alone, before reading a word.
import pf.Gui

Theme := [].{
	ground : Gui.Color
	ground = 0x14181b
	surface : Gui.Color
	surface = 0x1d2327
	raised : Gui.Color
	raised = 0x262e34
	hairline : Gui.Color
	hairline = 0x38434a

	ink : Gui.Color
	ink = 0xe6ebee
	muted : Gui.Color
	muted = 0x8e9ba4
	absent : Gui.Color
	absent = 0x5c6971

	## Connected, and nothing else.
	link : Gui.Color
	link = 0x6fc39a
	link_tint : Gui.Color
	link_tint = 0x142620
	link_deep : Gui.Color
	link_deep = 0x2f7a5b
	on_link : Gui.Color
	on_link = 0x07150f

	## Held here, not on the device.
	pending : Gui.Color
	pending = 0xd9a760
	pending_tint : Gui.Color
	pending_tint = 0x2a2013
	pending_deep : Gui.Color
	pending_deep = 0x8a6428

	## Refused, or lost.
	alarm : Gui.Color
	alarm = 0xdd7f6d
	alarm_tint : Gui.Color
	alarm_tint = 0x281b18
	alarm_edge : Gui.Color
	alarm_edge = 0x5c3b34

	caption : Str -> Gui.Elem(a)
	caption = |text| Gui.row(
		{ padding: 0, gap: 0, font_size: 11, font_weight: 700, fg: muted },
		[Gui.text(text)],
	)

	note : Str -> Gui.Elem(a)
	note = |text| Gui.row(
		{ padding: 0, gap: 0, font_size: 13, fg: muted },
		[Gui.text(text)],
	)

	## Quiet supporting text, for the line that explains why a control cannot be
	## pressed or what a number is bounded by.
	aside : Str -> Gui.Elem(a)
	aside = |text| Gui.row(
		{ padding: 0, gap: 0, font_size: 11, fg: absent },
		[Gui.text(text)],
	)

	## Anything that is a number or an identifier, in the fixed-pitch face.
	figure : Str, U32, Gui.Color -> Gui.Elem(a)
	figure = |text, size, colour| Gui.row(
		{ padding: 0, gap: 0, font_size: size, font_face: Monospace, fg: colour },
		[Gui.text(text)],
	)

	## The link light. It reports one fact -- whether a handle is open -- and it
	## is the fastest thing in the window to read.
	dot : Gui.Color -> Gui.Elem(a)
	dot = |colour| Gui.row(
		{
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
	primary : Str, Str, Bool, (a, Gui.EventPress => Gui.Action(a)) -> Gui.Elem(a)
	primary = |face, label, enabled, on_press| Gui.button({
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
		hover_bg: 0x84d3ac,
		active_bg: link_deep,
		fg: on_link,
		disabled_bg: raised,
		disabled_fg: absent,
	})

	## Everything else.
	secondary : Str, Str, Bool, (a, Gui.EventPress => Gui.Action(a)) -> Gui.Elem(a)
	secondary = |face, label, enabled, on_press| Gui.button({
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
		hover_bg: 0x303a41,
		active_bg: 0x1e262b,
		fg: ink,
		border_color: hairline,
		border_width: 1,
		disabled_bg: surface,
		disabled_fg: absent,
	})

	panel : Str, Gui.Length, List(Gui.Elem(a)) -> Gui.Elem(a)
	panel = |label, width, children| Gui.panel(
		{
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
