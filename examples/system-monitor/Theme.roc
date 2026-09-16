## The monitor's visual vocabulary.
##
## An instrument panel is read at a glance and then read again a second later,
## so the design is built on one idea: nothing moves that is not a measurement.
## Every surface is a fixed size, every figure is set in the fixed-pitch face,
## and colour is spent on one thing only -- telling the eye that a number has
## crossed a line it cares about. Four different hues for four metrics would be
## decoration, and would leave nothing distinctive for a threshold to use.
import pf.Elem
import pf.Gui

Theme := [].{
	## The ground the window is painted on, and the two surfaces that sit on it.
	## Two steps is enough to separate a panel from the page and a row from its
	## panel; a third would start to look like depth for its own sake.
	ground = Gui.rgb(0x0d161b)
	surface = Gui.rgb(0x142229)
	raised = Gui.rgb(0x1b2f38)
	hairline = Gui.rgb(0x2a444f)

	## Reading text, supporting text, and the grey reserved for a value the
	## operating system declined to report. `absent` is deliberately darker than
	## `muted`: an unreported figure has to look less present than a caption.
	ink = Gui.rgb(0xdfe9ee)
	muted = Gui.rgb(0x8ba0aa)
	absent = Gui.rgb(0x516670)

	## The single accent. It means live -- sampling is running, this row is
	## selected, this sort is in force -- and it is used for nothing else.
	accent = Gui.rgb(0x63c0cf)
	accent_tint = Gui.rgb(0x11333c)
	accent_deep = Gui.rgb(0x2b7180)
	on_accent = Gui.rgb(0x07171c)

	## The two thresholds. Nothing else in the application is warm, so a warm
	## figure is always a figure worth looking at.
	warn = Gui.rgb(0xd9a05b)
	alert = Gui.rgb(0xde7f6d)

	## A small caption over the thing it names. Set in the proportional face,
	## because a caption is a word rather than a measurement.
	caption : Str -> Elem.Elem(a)
	caption = |text| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: 11, font_weight: 700, fg: muted },
		[Elem.text(text)],
	)

	## Ordinary supporting prose.
	note : Str -> Elem.Elem(a)
	note = |text| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: 13, fg: muted },
		[Elem.text(text)],
	)

	## A measurement. Everything that is a number goes through here, so no figure
	## in the application is ever set in a proportional face.
	figure : Str, U32, Gui.Color -> Elem.Elem(a)
	figure = |text, size, colour| Elem.row(
		Elem.RowProps.{ padding: 0, gap: 0, font_size: size, font_face: Monospace, fg: colour },
		[Elem.text(text)],
	)

	## A filled disc. The only piece of pure artwork in the window, and it earns
	## its place: it says whether the instrument is live before any word does,
	## and it is the one thing on screen that is allowed to change colour often.
	dot : Gui.Color -> Elem.Elem(a)
	dot = |colour| Elem.row(
		Elem.RowProps.{
			label: "Sampling indicator",
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

	## A horizontal rule, used where a border would have to be drawn on one side
	## of a container that also needs a background.
	rule : Gui.Color, U32 -> Elem.Elem(a)
	rule = |colour, thickness| Elem.row(
		Elem.RowProps.{ width: Fill, height: Px(thickness), min_height: Px(thickness), padding: 0, gap: 0, bg: colour },
		[],
	)

	## A panel: the standard surface everything in the body sits on.
	panel : Str, List(Elem.Elem(a)) -> Elem.Elem(a)
	panel = |label, children| Elem.panel(
		Elem.PanelProps.{
			label,
			width: Fill,
			padding: 16,
			gap: 12,
			radius: 12,
			bg: surface,
			border_color: hairline,
			fg: ink,
			font_size: 14,
		},
		children,
	)
}
