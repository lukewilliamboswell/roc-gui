## The text, table, and control pieces the Compare and Scaling views are
## built from, drawn exactly as the other views draw theirs: one-line rows,
## fixed-width columns whose figures share a rule with their heading, and
## fixed-pitch figures.
import pf.Gui
import Observatory
import Theme

Elem : Gui.Elem(Observatory.State)

Widgets := [].{
	meta : Str -> Elem
	meta = |caption| Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(caption)])

	note : Str -> Elem
	note = |caption| Gui.col({ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(caption)])

	## A line a specification can name. It wraps to the width it is given,
	## so a narrow inspector keeps all of it.
	labelled_note : Str, Str, Gui.Color -> Elem
	labelled_note = |label, caption, ink| Gui.row({ label, width: Fill, padding: 0, gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face }, [Gui.col({ width: Fill, grow: True, min_width: Px(0), padding: 0, gap: 0 }, [Gui.text(caption)])])

	heading : Str -> Elem
	heading = |caption| Gui.row({ width: Fill, padding: 0, padding_top: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(caption)])

	cell : Str, U32, Gui.Color -> Elem
	cell = |text, width, ink| column_cell({ width, justify: Start, ink, size: Theme.body }, [Gui.text(text)])

	## A cell a specification can name.
	labelled_cell : Str, Str, U32, Gui.Color -> Elem
	labelled_cell = |label, text, width, ink| Gui.row({ label, width: Px(width), min_width: Px(width), max_width: Px(width), padding: 0, gap: 0, align: Center }, [column_cell({ width, justify: Start, ink, size: Theme.body }, [Gui.text(text)])])

	figure_cell : Str, U32, Gui.Color -> Elem
	figure_cell = |text, width, ink| column_cell({ width, justify: End, ink, size: Theme.body }, [Gui.text(text)])

	## A cell holding any element, such as a button or a bar.
	holder : U32, List(Elem) -> Elem
	holder = |width, children| column_cell({ width, justify: Start, ink: Theme.ink, size: Theme.body }, children)

	rest_cell : Str, Gui.Color -> Elem
	rest_cell = |text, ink| Gui.row(
		{ width: Fill, grow: True, overflow_x: Clip, padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
		[Gui.text(text)],
	)

	labelled_row : Str, List(Elem) -> Elem
	labelled_row = |label, cells| Gui.row(
		{ label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		cells,
	)

	table_head : Str, List(Elem) -> Elem
	table_head = |label, cells| Gui.row(
		{ label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		cells,
	)

	head_cell : Str, U32 -> Elem
	head_cell = |text, width| column_cell({ width, justify: Start, ink: Theme.dim, size: Theme.meta }, [Gui.text(text)])

	head_figure : Str, U32 -> Elem
	head_figure = |text, width| column_cell({ width, justify: End, ink: Theme.dim, size: Theme.meta }, [Gui.text(text)])

	head_rest : Str -> Elem
	head_rest = |text| Gui.row({ width: Fill, grow: True, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center }, [Gui.text(text)])

	table : Str, List(Elem) -> Elem
	table = |label, children| Gui.col({ label, width: Fill, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius }, children)

	key : { caption : Str, label : Str, selected : Bool, on_press : Observatory.State, Gui.EventPress => Gui.Action(Observatory.State) } -> Elem
	key = |props| Gui.button({
		caption: props.caption,
		label: props.label,
		on_press: props.on_press,
		padding: 6,
		font_size: Theme.body,
		font_face: Theme.face,
		radius: Theme.radius,
		bg: if props.selected Theme.accent else Theme.quiet,
		hover_bg: if props.selected Theme.accent_hover else Theme.quiet_hover,
		active_bg: if props.selected Theme.accent_active else Theme.quiet_active,
		fg: if props.selected Theme.on_accent else Theme.ink,
		border_color: Theme.line,
		border_width: 1,
		text_overflow: Ellipsis,
	})

	## A small key inside a table row.
	row_key : { caption : Str, label : Str, selected : Bool, on_press : Observatory.State, Gui.EventPress => Gui.Action(Observatory.State) } -> Elem
	row_key = |props| Gui.button({
		caption: props.caption,
		label: props.label,
		on_press: props.on_press,
		padding: 2,
		font_size: Theme.meta,
		font_face: Theme.face,
		radius: Theme.radius,
		bg: if props.selected Theme.selected else Theme.card,
		hover_bg: Theme.quiet_hover,
		active_bg: Theme.quiet_active,
		fg: if props.selected Theme.ink else Theme.dim,
		border_color: Theme.line,
		border_width: 1,
	})

	chip : Str, Gui.Color -> Elem
	chip = |text, ink| Gui.row(
		{ padding: 3, padding_left: Px(6), padding_right: Px(6), gap: 0, fg: ink, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, font_size: Theme.meta, font_face: Theme.face },
		[Gui.text(text)],
	)

	block : U32, Gui.Color -> Elem
	block = |width, color| Gui.row({ width: Px(width), height: Px(10), padding: 0, gap: 0, bg: color }, [])

	pass_ink : Bool -> Gui.Color
	pass_ink = |pass| if pass Theme.good else Theme.alarm_ink

	pass_mark : Bool -> Str
	pass_mark = |pass| if pass "✓" else "✗"
}

column_cell : { width : U32, justify : Gui.Justify, ink : Gui.Color, size : U32 }, List(Elem) -> Elem
column_cell = |props, children| Gui.row(
	{ width: Px(props.width), min_width: Px(props.width), max_width: Px(props.width), padding: 0, padding_right: Px(Theme.inset), gap: 0, align: Center },
	[
		Gui.row(
			{ width: Fill, grow: True, overflow_x: Clip, padding: 0, gap: 0, fg: props.ink, font_size: props.size, font_face: Theme.face, text_overflow: Ellipsis, align: Center, justify: props.justify },
			children,
		),
	],
)
