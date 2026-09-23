## The mounted instrument: a header, the folder authority, the capture list, and
## for an open capture its bar, health banner, view rail, and the chosen view.
## Every figure is drawn from a measurement family; a family that is not
## `complete` is drawn as `—` with its status and reason beside it.
import pf.Gui
import Capture
import Format
import Observatory
import Theme

View := [].{
	render : Observatory.State -> Gui.Elem(Observatory.State)
	render = render
}

## Component boundaries. Every view is a keyed, memoized boundary over the
## whole state, and each compares only the inputs it draws: the capture's
## revision rather than its rows, and the few fields of navigation it reads. A
## change elsewhere then leaves its subtree and handlers in place, and a change
## a view makes to itself renders only that view.

boundary : Gui.Key, (Observatory.State, Observatory.State -> Bool), (Observatory.State -> Gui.Action(Observatory.State)), (Observatory.State -> Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
boundary = |key, same, policy, draw| Gui.translate_with(
	draw,
	{
		key,
		get: |state| state,
		set: |_, next| next,
		on_delegate: policy,
		memo: Some(same),
	},
)

## A boundary directly under the root, which fulfils what its views ask.
view_boundary : Str, (Observatory.State, Observatory.State -> Bool), (Observatory.State -> Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
view_boundary = |name, same, draw| boundary(Gui.Key.from_str(name), same, Observatory.fulfil, draw)

## A boundary inside a view, which forwards requests toward the root.
part_boundary : Str, (Observatory.State, Observatory.State -> Bool), (Observatory.State -> Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
part_boundary = |name, same, draw| boundary(Gui.Key.from_str(name), same, Observatory.forward, draw)

revision_of : [None, Some(Capture.Opened)] -> [None, Some(U64)]
revision_of = |capture| match capture {
	Some(opened) => Some(opened.revision)
	None => None
}

folder_revision : [None, Some(Observatory.Folder)] -> [None, Some(U64)]
folder_revision = |folder| match folder {
	Some(found) => Some(found.revision)
	None => None
}

same_capture : Observatory.State, Observatory.State -> Bool
same_capture = |a, b| revision_of(a.capture) == revision_of(b.capture)

## The cycle list compares the read that produced its rows and the row it was
## last asked to show, not the rows.
same_cycles : Observatory.State, Observatory.State -> Bool
same_cycles = |a, b| Observatory.listed_cycles(a).read == Observatory.listed_cycles(b).read and a.cycle_scroll == b.cycle_scroll

inspected_id : Observatory.State -> [None, Some(I64)]
inspected_id = |state| match state.inspected {
	Some(inspected) => Some(inspected.cycle.id)
	None => None
}

## A view of the open capture. With no capture it draws nothing, which only a
## stale boundary could ask for.
with_capture : Observatory.State, (Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
with_capture = |state, draw| match state.capture {
	Some(opened) => draw(state, opened)
	None => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

## Text

meta : Str -> Gui.Elem(Observatory.State)
meta = |caption| Gui.row(
	{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

note : Str -> Gui.Elem(Observatory.State)
note = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta },
	[Gui.text(caption)],
)

line : Str -> Gui.Elem(Observatory.State)
line = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
	[Gui.text(caption)],
)

heading : Str -> Gui.Elem(Observatory.State)
heading = |caption| Gui.row(
	{ width: Fill, padding: 0, padding_top: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

verdict_ink : Capture.Verdict -> Gui.Color
verdict_ink = |verdict| match verdict {
	Complete => Theme.good
	Partial(_) => Theme.caution
	Untrusted(_) => Theme.alarm_ink
	Unsupported(_) => Theme.alarm_ink
}

verdict_badge : Capture.Verdict -> Str
verdict_badge = |verdict| match verdict {
	Complete => "✓ complete"
	Partial(_) => "⚠ partial"
	Untrusted(_) => "✗ untrusted"
	Unsupported(reason) => "✗ ${reason}"
}

## Tables. A cell clips rather than wraps, so every row is one line tall and a
## column's figures sit on the same vertical rule as its heading.

## A fixed-width column. The gutter sits outside the clip, so a clipped value
## never runs into its neighbour.
column_cell : { width : U32, justify : Gui.Justify, ink : Gui.Color, size : U32 }, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
column_cell = |props, children| Gui.row(
	{ width: Px(props.width), min_width: Px(props.width), max_width: Px(props.width), padding: 0, padding_right: Px(Theme.inset), gap: 0, align: Center },
	[
		Gui.row(
			{ width: Fill, grow: True, overflow_x: Clip, padding: 0, gap: 0, fg: props.ink, font_size: props.size, font_face: Theme.face, text_overflow: Ellipsis, align: Center, justify: props.justify },
			children,
		),
	],
)

cell : Str, U32, Gui.Color -> Gui.Elem(Observatory.State)
cell = |text, width, ink| column_cell({ width, justify: Start, ink, size: Theme.body }, [Gui.text(text)])

figure_cell : Str, U32 -> Gui.Elem(Observatory.State)
figure_cell = |text, width| column_cell({ width, justify: End, ink: Theme.ink, size: Theme.body }, [Gui.text(text)])

rest_cell : Str, Gui.Color -> Gui.Elem(Observatory.State)
rest_cell = |text, ink| Gui.row(
	{ width: Fill, grow: True, overflow_x: Clip, padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
	[Gui.text(text)],
)

table_row : List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table_row = |cells| Gui.row(
	{ width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

## A row a specification can name.
labelled_row : Str, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
labelled_row = |label, cells| Gui.row(
	{ label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

table_head : Str, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table_head = |label, cells| Gui.row(
	{ label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

head_cell : Str, U32 -> Gui.Elem(Observatory.State)
head_cell = |text, width| column_cell({ width, justify: Start, ink: Theme.dim, size: Theme.meta }, [Gui.text(text)])

head_figure : Str, U32 -> Gui.Elem(Observatory.State)
head_figure = |text, width| column_cell({ width, justify: End, ink: Theme.dim, size: Theme.meta }, [Gui.text(text)])

head_rest : Str -> Gui.Elem(Observatory.State)
head_rest = |text| Gui.row(
	{ width: Fill, grow: True, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center },
	[Gui.text(text)],
)

table : Str, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table = |label, children| Gui.col(
	{ label, width: Fill, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
	children,
)

## Controls

key : { caption : Str, label : Str, selected : Bool, on_press : Observatory.State, Gui.EventPress => Gui.Action(Observatory.State) } -> Gui.Elem(Observatory.State)
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

## An absent value. It is a `—`, never a zero, and pressing it opens Health at
## the family that explains it.
dash : Str, U32 -> Gui.Elem(Observatory.State)
dash = |family_name, font_size| Gui.button({
	caption: "—",
	label: "Why ${family_name}",
	on_press: |current, _| Observatory.ask(current, ShowFamily(family_name)),
	padding: 0,
	font_size,
	font_face: Theme.face,
	radius: 0,
	bg: Theme.card,
	hover_bg: Theme.quiet_hover,
	active_bg: Theme.quiet_active,
	fg: Theme.ink,
	border_width: 0,
})

dash_cell : Str, U32 -> Gui.Elem(Observatory.State)
dash_cell = |family_name, width| column_cell({ width, justify: End, ink: Theme.ink, size: Theme.body }, [dash(family_name, Theme.body)])

## A figure from one family: its text when the family is complete, otherwise a
## `—` that opens Health at the family.
family_cell : Bool, Str, Str, U32 -> Gui.Elem(Observatory.State)
family_cell = |present, family_name, text, width| if present figure_cell(text, width) else dash_cell(family_name, width)

## The line beside a table whose values are absent.
absence_note : Capture.Opened, Str -> Gui.Elem(Observatory.State)
absence_note = |opened, family_name| absence_line(family_name, Capture.absence(opened, family_name))

absence_line : Str, Str -> Gui.Elem(Observatory.State)
absence_line = |family_name, reason| Gui.row(
	{ label: "Absent ${family_name}", width: Fill, padding: 0, gap: 6, align: Center, fg: Theme.dim, font_size: Theme.meta },
	[dash(family_name, Theme.meta), Gui.text(reason)],
)

## Sorting. Numbers order before text, and text orders by its bytes.

SortKey : [Text(Str), Number(I64)]

compare_text : Str, Str -> [Before, Same, After]
compare_text = |left, right| {
	left_bytes = left.to_utf8()
	right_bytes = right.to_utf8()
	var $result = Same
	for item in List.map2(left_bytes, right_bytes, |a, b| if a < b Before else if a > b After else Same) {
		if $result == Same {
			$result = item
		}
	}
	if $result == Same {
		if left_bytes.len() < right_bytes.len() Before else if left_bytes.len() > right_bytes.len() After else Same
	} else {
		$result
	}
}

compare_keys : SortKey, SortKey -> [Before, Same, After]
compare_keys = |left, right| match (left, right) {
	(Number(a), Number(b)) => if a < b Before else if a > b After else Same
	(Text(a), Text(b)) => compare_text(a, b)
	(Number(_), Text(_)) => Before
	(Text(_), Number(_)) => After
}

reverse_order : [Before, Same, After] -> [Before, Same, After]
reverse_order = |order| match order {
	Before => After
	After => Before
	Same => Same
}

number_or_text : Str -> SortKey
number_or_text = |text| match I64.from_str(text) {
	Ok(number) => Number(number)
	Err(_) => Text(text)
}

## The caption of the column a table is ordered by.
sort_caption : List(Column), Observatory.Sort -> Str
sort_caption = |columns, sort| match columns.get(sort.column) {
	Ok(column) => column.caption
	Err(_) => ""
}

## A column heading that orders its table. The active column carries its
## direction.
sort_head : { caption : Str, label : Str, width : [Px(U32), Rest], figure : Bool, sort : Observatory.Sort, column : U64, on_press : Observatory.State -> Observatory.State } -> Gui.Elem(Observatory.State)
sort_head = |props| {
	active = props.sort.column == props.column
	arrow = if !active "" else if props.sort.descending " ▾" else " ▴"
	handler = props.on_press
	button = Gui.button({
		caption: "${props.caption}${arrow}",
		label: props.label,
		on_press: |current, _| Gui.update(handler(current)),
		padding: 0,
		font_size: Theme.meta,
		font_face: Theme.face,
		radius: Theme.radius,
		bg: Theme.rail,
		hover_bg: Theme.quiet_hover,
		active_bg: Theme.quiet_active,
		fg: if active Theme.ink else Theme.dim,
		border_width: 0,
	})
	match props.width {
		Px(width) => column_cell({ width, justify: if props.figure End else Start, ink: Theme.dim, size: Theme.meta }, [button])
		Rest => Gui.row({ width: Fill, grow: True, padding: 0, gap: 0, align: Center }, [button])
	}
}

## Bars. A measured part is a sized block; its width is its share of `whole`
## across `span` pixels, and any non-zero part is at least one pixel wide.

scaled : I64, I64, U32 -> U32
scaled = |part, whole, span| if whole <= 0 or part <= 0 {
	0
} else {
	width = part * span.to_i64() / whole
	if width < 1 1 else width.to_u32_wrap()
}

block : U32, Gui.Color -> Gui.Elem(Observatory.State)
block = |width, color| Gui.row({ width: Px(width), height: Px(10), padding: 0, gap: 0, bg: color }, [])

## One bar at an offset within a track, as a waterfall row draws it.
offset_bar : { offset : I64, part : I64, whole : I64, span : U32, color : Gui.Color } -> Gui.Elem(Observatory.State)
offset_bar = |props| Gui.row(
	{ width: Px(props.span), padding: 0, gap: 0, align: Center },
	[block(scaled(props.offset, props.whole, props.span), Theme.card), block(scaled(props.part, props.whole, props.span), props.color)],
)

## Header and authority

header : Observatory.State -> Gui.Elem(Observatory.State)
header = |state| {
	right = match state.status {
		Busy(_) => "reading…"
		_ => match state.capture {
			Some(opened) => opened.name
			None => "no capture open"
		}
	}
	Gui.row(
		{ label: "Observatory header", width: Fill, padding: Theme.inset, gap: 8, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1), fg: Theme.ink, font_size: Theme.meta },
		[
			Gui.text("OBSERVATORY"),
			meta("roc-gui captures, schema ${Capture.supported_schema}, read only"),
			Gui.row({ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(right)]),
		],
	)
}

authority_bar : Observatory.State -> Gui.Elem(Observatory.State)
authority_bar = |state| {
	reading = match state.grant {
		Ungranted => { held: "no folder granted", verdict: "choose a folder of captures", ink: Theme.dim }
		Declined => { held: "no folder granted", verdict: "you closed the picker without choosing", ink: Theme.dim }
		Granted(folder) => { held: folder, verdict: "read-only, this folder only", ink: Theme.ink }
		Refused => { held: "no folder granted", verdict: "the host refused a folder", ink: Theme.alarm_ink }
	}
	Gui.row(
		{ label: "Authority bar", width: Fill, padding: Theme.inset, gap: Theme.inset, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1), font_size: Theme.meta },
		[
			meta("FOLDER"),
			Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.meta, font_face: Theme.face, max_width: Px(320), text_overflow: Ellipsis }, [Gui.text(reading.held)]),
			Gui.row({ label: "Folder verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta }, [Gui.text(reading.verdict)]),
			key({ caption: "Open capture…", label: "Open capture", selected: False, on_press: |current, _| Observatory.choose_file(current) }),
			key({ caption: "Open folder…", label: "Open folder", selected: False, on_press: |current, _| Observatory.choose(current) }),
		],
	)
}

error_band : Observatory.State -> Gui.Elem(Observatory.State)
error_band = |state| match state.status {
	Failed(problem) => Gui.panel(
		{ label: "Capture error", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, fg: Theme.alarm_ink, border_color: Theme.alarm_line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[
			Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text(problem.message)]),
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(problem.remedy)]),
		],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

## The capture list (W0)

capture_row : Capture.Listing -> Gui.Elem(Observatory.State)
capture_row = |listing| Gui.row(
	{ label: "Capture row ${listing.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[
		Gui.row(
			{ width: Px(250), min_width: Px(250), max_width: Px(250), overflow_x: Clip, padding: 0, padding_right: Px(Theme.inset), gap: 0 },
			[
				Gui.button({
					caption: listing.name,
					label: "Capture ${listing.name}",
					on_press: |current, _| Observatory.ask(current, Open(listing.name)),
					width: Fill,
					padding: 0,
					font_size: Theme.body,
					font_face: Theme.face,
					radius: Theme.radius,
					bg: Theme.card,
					hover_bg: Theme.quiet_hover,
					active_bg: Theme.quiet_active,
					fg: Theme.accent,
					border_color: Theme.line,
					border_width: 0,
					text_overflow: Ellipsis,
					justify: Start,
				}),
			],
		),
		cell(listing.application, 150, Theme.ink),
		cell(listing.spec, 260, Theme.ink),
		cell(listing.backend, 150, Theme.dim),
		figure_cell(listing.scale, 70),
		cell(listing.detail, 80, Theme.dim),
		rest_cell(verdict_badge(listing.verdict), verdict_ink(listing.verdict)),
	],
)

Column : { caption : Str, width : [Px(U32), Rest], figure : Bool }

capture_columns : List(Column)
capture_columns = [
	{ caption: "file", width: Px(250), figure: False },
	{ caption: "app", width: Px(150), figure: False },
	{ caption: "spec", width: Px(260), figure: False },
	{ caption: "backend", width: Px(150), figure: False },
	{ caption: "scale", width: Px(70), figure: True },
	{ caption: "detail", width: Px(80), figure: False },
	{ caption: "health", width: Rest, figure: False },
]

capture_heads : Observatory.Sort -> List(Gui.Elem(Observatory.State))
capture_heads = |sort| capture_columns.map_with_index(
	|column, index| sort_head({
		caption: column.caption,
		label: "Sort captures by ${column.caption}",
		width: column.width,
		figure: column.figure,
		sort,
		column: index,
		on_press: |current| Observatory.sort_captures(current, index),
	}),
)

capture_key : Capture.Listing, U64 -> SortKey
capture_key = |listing, column| match column {
	0 => Text(listing.name)
	1 => Text(listing.application)
	2 => Text(listing.spec)
	3 => Text(listing.backend)
	4 => number_or_text(listing.scale)
	5 => Text(listing.detail)
	_ => Text(verdict_badge(listing.verdict))
}

sorted_captures : List(Capture.Listing), Observatory.Sort -> List(Capture.Listing)
sorted_captures = |captures, sort| List.sort_with(
	captures,
	|left, right| {
		order = compare_keys(capture_key(left, sort.column), capture_key(right, sort.column))
		if sort.descending reverse_order(order) else order
	},
)

## Only the rows near the viewport are built, so a folder of a thousand
## captures costs what a screenful does.
captures_rows : List(Capture.Listing) -> Gui.Elem(Observatory.State)
captures_rows = |sorted| Gui.virtual_rows({
	label: "Captures",
	row_height: Theme.row_height,
	count: sorted.len(),
	render_row: |index| match sorted.get(index) {
		Ok(listing) => capture_row(listing)
		Err(_) => table_row([])
	},
})

capture_list : Observatory.State -> Gui.Elem(Observatory.State)
capture_list = |state| {
	body = match state.folder {
		None => [note("Open one .rgstats capture, or choose a folder of them, such as a benchmark output directory.")]
		Some(folder) => if folder.captures.is_empty() {
			[note("The folder holds no .rgstats captures.")]
		} else {
			[
				meta("CAPTURES IN ${folder.name} · ${folder.captures.len().to_str()}"),
				Gui.col(
					{ label: "Capture table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
					[
						table_head("Capture columns", capture_heads(state.capture_sort)),
						captures_rows(sorted_captures(folder.captures, state.capture_sort)),
					],
				),
			]
		}
	}
	Gui.col(
		{ label: "Start", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset, bg: Theme.paper },
		body,
	)
}

## The capture bar and the health banner (US-6)

chip : Str, Gui.Color -> Gui.Elem(Observatory.State)
chip = |text, ink| Gui.row(
	{ padding: 3, padding_left: Px(6), padding_right: Px(6), gap: 0, fg: ink, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(text)],
)

capture_bar : Capture.Opened -> Gui.Elem(Observatory.State)
capture_bar = |opened| {
	final = Capture.metadata(opened, "final_state")
	clean = Capture.metadata(opened, "clean_shutdown")
	gaps = opened.gaps.len()
	Gui.row(
		{ label: "Capture bar", width: Fill, padding: Theme.inset, gap: 6, align: Center, bg: Theme.paper, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		[
			key({ caption: "‹ Captures", label: "Back to captures", selected: False, on_press: |current, _| Observatory.ask(current, CloseCapture) }),
			Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, max_width: Px(260), text_overflow: Ellipsis }, [Gui.text(opened.name)]),
			chip(Capture.metadata(opened, "backend"), Theme.ink),
			chip(Capture.metadata(opened, "effective_detail"), Theme.ink),
			chip("schema ${Capture.metadata(opened, "schema_version")}", Theme.ink),
			chip(if final == "complete" "✓ final" else "not finalised", if final == "complete" Theme.good else Theme.alarm_ink),
			chip(if clean == "1" "clean shutdown" else "unclean shutdown", if clean == "1" Theme.good else Theme.alarm_ink),
			chip("gaps ${gaps.to_str()}", if gaps == 0 Theme.good else Theme.alarm_ink),
			chip(Capture.metadata(opened, "timing_quality"), if Capture.metadata(opened, "timing_quality") == "isolated" Theme.ink else Theme.caution),
			Gui.row({ padding: 0, gap: 0, grow: True, justify: End }, [chip(verdict_badge(opened.verdict), verdict_ink(opened.verdict))]),
		],
	)
}

banner : Capture.Opened -> Gui.Elem(Observatory.State)
banner = |opened| match opened.verdict {
	Untrusted(cause) => Gui.panel(
		{ label: "Untrusted capture", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, fg: Theme.alarm_ink, border_color: Theme.alarm_line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text("Untrusted capture: ${cause}")])],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

nav : Observatory.State -> Gui.Elem(Observatory.State)
nav = |state| {
	entry = |caption, view| key({ caption, label: caption, selected: state.view == view, on_press: |current, _| Observatory.ask(current, Show(view)) })
	Gui.col(
		{ label: "Views", width: Px(Theme.nav_width), height: Fill, padding: Theme.inset, gap: 6, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_right: Px(1) },
		[meta("VIEWS"), entry("Overview", Overview), entry("Interactions", Interactions), entry("Spec", Spec), entry("Memory", Memory), entry("Health", Health)],
	)
}

## Overview (W1)

## A tile's figure. An absent one is a `—` that opens Health at its family,
## and its reason wraps in full beneath it.
tile : { name : Str, family : Str, value : Str, detail : Str, opens : Str, view : Observatory.View } -> Gui.Elem(Observatory.State)
tile = |props| Gui.panel(
	{ label: "Tile ${props.name}", width: Fill, grow: True, padding: Theme.inset, gap: 4, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
	[
		meta(props.name),
		if props.value == "—" {
			Gui.row({ padding: 0, gap: 0 }, [dash(props.family, Theme.figure)])
		} else {
			Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.figure, font_face: Theme.face, text_overflow: Ellipsis }, [Gui.text(props.value)])
		},
		Gui.row({ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(props.detail)]),
		key({ caption: "${props.opens} ›", label: "Open ${props.name}", selected: False, on_press: |current, _| Observatory.ask(current, Show(props.view)) }),
	],
)

## A figure from one family: its value when the family is complete, otherwise
## `—` and the family's status and reason.
measured : Capture.Opened, Str, { value : Str, detail : Str } -> { value : Str, detail : Str }
measured = |opened, name, present| if Capture.complete(opened, name) present else { value: "—", detail: Capture.absence(opened, name) }

identity : Capture.Opened -> List(Gui.Elem(Observatory.State))
identity = |opened| {
	m = |name| Capture.metadata(opened, name)
	commit = m("host_commit")
	short = if Str.is_empty(commit) "unavailable" else Str.from_utf8(commit.to_utf8().take_first(7)) ?? commit
	dirty = match m("host_dirty") {
		"1" => " (dirty)"
		"0" => ""
		_ => " (dirty unknown)"
	}
	samples = m("benchmark_samples")
	benchmark = if samples == "0" or Str.is_empty(samples) {
		"not a benchmark: one test run"
	} else {
		"benchmark: ${m("benchmark_warmups")} warmups · ${samples} samples · ${m("benchmark_iterations")} iterations · scale ${m("benchmark_scale")}"
	}
	[
		line("${m("app_name")} · spec \"${m("spec_name")}\" · ${m("target_profile")}"),
		line("commit ${short}${dirty} · ${m("cpu_model")} ×${m("logical_cpu_count")} · ${m("host_os")} ${m("host_arch")}"),
		line(benchmark),
	]
}

overview : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
overview = |state, opened| {
	passed = opened.runs.keep_if(|run| run.outcome == "pass").len()
	outcome = measured(opened, "test_outcome", { value: "${passed.to_str()}/${opened.runs.len().to_str()} runs pass", detail: "${opened.runs.fold(0.I64, |total, run| total + run.steps).to_str()} steps" })
	phase_triggers = opened.triggers.keep_if(|trigger| trigger.phase == state.phase)
	slowest_found = List.sort_with(phase_triggers, |left, right| if left.median > right.median Before else if left.median < right.median After else Same).first()
	slowest = measured(
		opened,
		"host_cycles",
		match slowest_found {
			Ok(found) => { value: "${found.trigger}", detail: "${found.patch_kind} · median ${Format.ms(found.median)} · max ${Format.ms(found.max)}" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	median = measured(
		opened,
		"host_cycles",
		match opened.medians.find_first(|found| found.phase == state.phase) {
			Ok(found) => { value: Format.ms(found.median), detail: "${found.count.to_str()} ${state.phase} cycles" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	frames = measured(
		opened,
		"gpui_frame_spans",
		{ value: "${opened.frames.over_budget.to_str()} of ${opened.frames.drawn.to_str()}", detail: "host-owned stages over 16.7 ms" },
	)
	skip = measured(
		opened,
		"component_work",
		match opened.skips.find_first(|found| found.phase == state.phase) {
			Ok(found) => { value: Format.percent(found.skipped, found.compared), detail: "${found.skipped.to_str()} of ${found.compared.to_str()} compared skipped" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	Gui.col(
		{ label: "Overview", width: Fill, padding: Theme.inset, gap: 6 },
		[heading("IDENTITY")]
			.concat(identity(opened))
			.concat(
				[
					heading("${state.phase} phase"),
					Gui.row(
						{ label: "Tiles", width: Fill, padding: 0, gap: Theme.inset },
						[
							tile({ name: "Outcome", family: "test_outcome", value: outcome.value, detail: outcome.detail, opens: "Spec", view: Spec }),
							tile({ name: "Slowest trigger", family: "host_cycles", value: slowest.value, detail: slowest.detail, opens: "Interactions", view: Interactions }),
							tile({ name: "Median cycle", family: "host_cycles", value: median.value, detail: median.detail, opens: "Interactions", view: Interactions }),
						],
					),
					Gui.row(
						{ label: "More tiles", width: Fill, padding: 0, gap: Theme.inset },
						[
							tile({ name: "Frames over budget", family: "gpui_frame_spans", value: frames.value, detail: frames.detail, opens: "Health", view: Health }),
							tile({ name: "Skip rate", family: "component_work", value: skip.value, detail: skip.detail, opens: "Health", view: Health }),
							tile({ name: "Verdict", family: "", value: Capture.verdict_word(opened.verdict), detail: Capture.verdict_reason(opened.verdict), opens: "Health", view: Health }),
						],
					),
				],
			),
	)
}

## Interactions (W2): the triggers table, the slowest cycles, and the inspector

phases : List(Str)
phases = ["initialization", "setup", "measured", "interactive"]

## A view whose phase is its own changes it in place; Interactions asks for the
## cycles of the phase it chooses to be read.
phase_selector : Observatory.State, (Observatory.State, Str -> Gui.Action(Observatory.State)) -> Gui.Elem(Observatory.State)
phase_selector = |state, choose_phase| Gui.row(
	{ label: "Phase", width: Fill, padding: 0, gap: 6, align: Center },
	[meta("PHASE")].concat(phases.map(|phase| key({ caption: phase, label: "Phase ${phase}", selected: state.phase == phase, on_press: |current, _| choose_phase(current, phase) }))),
)

trigger_columns : List(Column)
trigger_columns = [
	{ caption: "trigger", width: Px(180), figure: False },
	{ caption: "patch", width: Px(110), figure: False },
	{ caption: "cycles", width: Px(70), figure: True },
	{ caption: "min", width: Px(110), figure: True },
	{ caption: "median", width: Px(110), figure: True },
	{ caption: "max", width: Px(110), figure: True },
	{ caption: "IQR", width: Px(110), figure: True },
]

trigger_key : Capture.Trigger, U64 -> SortKey
trigger_key = |trigger, column| match column {
	0 => Text(trigger.trigger)
	1 => Text(trigger.patch_kind)
	2 => Number(trigger.count)
	3 => Number(trigger.min)
	4 => Number(trigger.median)
	5 => Number(trigger.max)
	_ => Number(trigger.iqr)
}

sorted_triggers : List(Capture.Trigger), Observatory.Sort -> List(Capture.Trigger)
sorted_triggers = |triggers, sort| List.sort_with(
	triggers,
	|left, right| {
		order = compare_keys(trigger_key(left, sort.column), trigger_key(right, sort.column))
		if sort.descending reverse_order(order) else order
	},
)

trigger_heads : Observatory.Sort -> List(Gui.Elem(Observatory.State))
trigger_heads = |sort| trigger_columns
	.map_with_index(
		|column, index| sort_head({
			caption: column.caption,
			label: "Sort triggers by ${column.caption}",
			width: column.width,
			figure: column.figure,
			sort,
			column: index,
			on_press: |current| Observatory.sort_triggers(current, index),
		}),
	)
	.append(head_rest("cycle list"))

## Pressing a trigger's filter shows only its cycles; pressing it again shows
## every trigger of the phase.
trigger_filter : Observatory.State, Capture.Trigger -> Gui.Elem(Observatory.State)
trigger_filter = |state, trigger| {
	chosen = state.filter == Only({ trigger: trigger.trigger, patch_kind: trigger.patch_kind })
	Gui.row(
		{ width: Fill, grow: True, padding: 0, gap: 0, align: Center },
		[
			Gui.button({
				caption: if chosen "✓ only these" else "only these",
				label: "Filter ${trigger.trigger} ${trigger.patch_kind}",
				on_press: |current, _| Observatory.ask(current, FilterTrigger(trigger.trigger, trigger.patch_kind)),
				padding: 2,
				font_size: Theme.meta,
				font_face: Theme.face,
				radius: Theme.radius,
				bg: if chosen Theme.selected else Theme.card,
				hover_bg: Theme.quiet_hover,
				active_bg: Theme.quiet_active,
				fg: if chosen Theme.ink else Theme.dim,
				border_color: Theme.line,
				border_width: 1,
			}),
		],
	)
}

triggers_table : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
triggers_table = |state, opened| {
	timed = Capture.complete(opened, "host_cycles")
	shown = |ns, width| family_cell(timed, "host_cycles", Format.ms(ns), width)
	rows = sorted_triggers(opened.triggers.keep_if(|trigger| trigger.phase == state.phase), state.trigger_sort)
	body = if rows.is_empty() {
		[note("No cycles were recorded in the ${state.phase} phase.")]
	} else {
		rows.map(
			|trigger| table_row([
				cell(trigger.trigger, 180, Theme.ink),
				cell(trigger.patch_kind, 110, Theme.dim),
				family_cell(timed, "host_cycles", trigger.count.to_str(), 70),
				shown(trigger.min, 110),
				shown(trigger.median, 110),
				shown(trigger.max, 110),
				shown(trigger.iqr, 110),
				trigger_filter(state, trigger),
			]),
		)
	}
	absence = if timed [] else [absence_note(opened, "host_cycles")]
	[heading("TRIGGERS · ${state.phase} · by ${sort_caption(trigger_columns, state.trigger_sort)} · warmups excluded")]
		.concat(absence)
		.concat([table("Triggers", [table_head("Trigger columns", trigger_heads(state.trigger_sort))].concat(body))])
}

## The slowest cycles (US-10)

cycle_name : Capture.Cycle -> Str
cycle_name = |cycle| "r${cycle.run_id.to_str()} #${cycle.ordinal.to_str()}"

bar_span : U32
bar_span = 320

## Callback, validate, apply, and the rest of the cycle no owner attributed,
## drawn to one scale so rows compare.
stacked_bar : Capture.Cycle, I64 -> Gui.Elem(Observatory.State)
stacked_bar = |cycle, slowest| {
	rest = cycle.duration - cycle.callback - cycle.validate - cycle.apply
	Gui.row(
		{ label: "Cycle bar ${cycle_name(cycle)}", width: Fill, grow: True, padding: 0, gap: 0, align: Center },
		[
			block(scaled(cycle.callback, slowest, bar_span), Theme.callback),
			block(scaled(cycle.validate, slowest, bar_span), Theme.validate),
			block(scaled(cycle.apply, slowest, bar_span), Theme.apply),
			block(scaled(rest, slowest, bar_span), Theme.unattributed),
		],
	)
}

is_chosen : Observatory.State, I64 -> Bool
is_chosen = |state, id| inspected_id(state) == Some(id)

## Each row is its own boundary, keyed by its cycle, so opening a cycle
## renders the two rows whose selection changed and retains the rest.
cycle_boundary : Capture.Cycle, I64, Bool -> Gui.Elem(Observatory.State)
cycle_boundary = |cycle, slowest, timed| boundary(
	Gui.Key.id(cycle.id.to_u64_wrap()),
	|a, b| same_capture(a, b) and a.phase == b.phase and a.filter == b.filter and is_chosen(a, cycle.id) == is_chosen(b, cycle.id),
	Observatory.forward,
	|current| cycle_row(is_chosen(current, cycle.id), cycle, slowest, timed),
)

cycle_row : Bool, Capture.Cycle, I64, Bool -> Gui.Elem(Observatory.State)
cycle_row = |chosen, cycle, slowest, timed| {
	Gui.row(
		{ label: "Cycle row ${cycle_name(cycle)}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: if chosen Theme.selected else Theme.card, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		[
			Gui.row(
				{ width: Px(100), padding: 0, padding_right: Px(Theme.inset), gap: 0 },
				[
					Gui.button({
						caption: cycle_name(cycle),
						label: "Cycle ${cycle_name(cycle)}",
						on_press: |current, _| Observatory.ask(current, Inspect(cycle)),
						width: Fill,
						padding: 2,
						font_size: Theme.body,
						font_face: Theme.face,
						radius: Theme.radius,
						bg: if chosen Theme.accent else Theme.card,
						hover_bg: if chosen Theme.accent_hover else Theme.quiet_hover,
						active_bg: if chosen Theme.accent_active else Theme.quiet_active,
						fg: if chosen Theme.on_accent else Theme.accent,
						border_color: Theme.line,
						border_width: 0,
						justify: Start,
					}),
				],
			),
			cell(cycle.trigger, 150, Theme.ink),
			cell(cycle.patch_kind, 90, Theme.dim),
			family_cell(timed, "host_cycles", Format.ms(cycle.duration), 110),
			if timed stacked_bar(cycle, slowest) else rest_cell("", Theme.dim),
		],
	)
}

legend_entry : Str, Gui.Color -> Gui.Elem(Observatory.State)
legend_entry = |caption, color| Gui.row(
	{ padding: 0, gap: 4, align: Center, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[block(10, color), Gui.text(caption)],
)

legend : Gui.Elem(Observatory.State)
legend = Gui.row(
	{ label: "Cycle legend", padding: 0, gap: Theme.inset, align: Center },
	[legend_entry("callback", Theme.callback), legend_entry("validate", Theme.validate), legend_entry("apply", Theme.apply), legend_entry("unattributed", Theme.unattributed)],
)

## A row whose cycle has not been read yet. It holds its place, and says so.
pending_row : U64 -> Gui.Elem(Observatory.State)
pending_row = |index| labelled_row("Cycle row pending ${(index + 1).to_str()}", [cell("…", 100, Theme.dim), rest_cell("reading", Theme.dim)])

## Rows that are not yet read have keys of their own, apart from every cycle's.
pending_key : U64 -> U64
pending_key = |index| index + 9223372036854775808

## Every cycle of the phase, slowest first. Only the rows near the viewport
## are built, and only the pages near it are read: the list asks for the page
## a viewport reaches as it reaches it.
cycles_section : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
cycles_section = |state, opened| {
	timed = Capture.complete(opened, "host_cycles")
	window = Observatory.listed_cycles(state)
	total = Observatory.cycle_total(state)
	# The bars share one scale: the slowest cycle of everything listed.
	slowest = Observatory.listed_triggers(state, opened).fold(0, |most, found| if found.max > most found.max else most)
	scope = match state.filter {
		All => "every trigger"
		Only(chosen) => "${chosen.trigger} · ${chosen.patch_kind}"
	}
	render_row : U64 -> Gui.Elem(Observatory.State)
	render_row = |index| match Observatory.row_at(window, index) {
		Some(cycle) => cycle_boundary(cycle, slowest, timed)
		None => pending_row(index)
	}
	row_key : U64 -> U64
	row_key = |index| match Observatory.row_at(window, index) {
		Some(cycle) => cycle.id.to_u64_wrap()
		None => pending_key(index)
	}
	jumps = if total > 1 {
		[
			key({ caption: "Slowest", label: "Scroll to slowest cycle", selected: False, on_press: |current, _| Observatory.ask(current, JumpToCycle(0, Start)) }),
			key({ caption: "Fastest", label: "Scroll to fastest cycle", selected: False, on_press: |current, _| Observatory.ask(current, JumpToCycle(total - 1, End)) }),
		]
	} else {
		[]
	}
	body = if total == 0 {
		[note("No ${state.phase} cycles to list.")]
	} else {
		[
			Gui.col(
				{ label: "Cycle table", width: Fill, height: Px(Theme.row_height * 9), padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
				[
					table_head("Cycle columns", [head_cell("cycle", 100), head_cell("trigger", 150), head_cell("patch", 90), head_figure("duration", 110), head_rest("callback · validate · apply · unattributed")]),
					Gui.virtual_rows({
						label: "Cycles",
						row_height: Theme.row_height,
						count: total,
						render_row,
						row_key,
						scroll_to: state.cycle_scroll,
						on_range: Some(
							|current, visible| match Observatory.cycles_wanted(current, visible) {
								Some(offset) => Observatory.ask(current, ReadCycles(offset))
								None => Gui.none
							},
						),
					}),
				],
			),
		]
	}
	[
		Gui.row(
			{ width: Fill, padding: 0, padding_top: Px(Theme.inset), gap: Theme.inset, align: Center },
			[meta("CYCLES · ${state.phase} · ${scope} · slowest first · ${total.to_str()}")]
				.concat(jumps)
				.append(Gui.row({ padding: 0, gap: 0, grow: True, justify: End }, [legend])),
		),
	]
		.concat(body)
}

## The cycle inspector (W3)

## One waterfall row: a name indented by depth, its duration, and its bar at
## its offset within the cycle.
waterfall_row : { name : Str, depth : U32, part : I64, offset : I64, whole : I64, color : Gui.Color } -> Gui.Elem(Observatory.State)
waterfall_row = |props| Gui.row(
	{ label: "Waterfall ${props.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset + props.depth * 16), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[
		cell(props.name, 220 - props.depth * 16, Theme.ink),
		figure_cell(Format.ms(props.part), 110),
		offset_bar({ offset: props.offset, part: props.part, whole: props.whole, span: 420, color: props.color }),
	],
)

## A waterfall row whose value is absent: its `—` and why.
waterfall_absent : { name : Str, depth : U32, family : Str, reason : Str } -> Gui.Elem(Observatory.State)
waterfall_absent = |props| Gui.row(
	{ label: "Waterfall ${props.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset + props.depth * 16), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[cell(props.name, 220 - props.depth * 16, Theme.ink), dash_cell(props.family, 110), rest_cell(props.reason, Theme.dim)],
)

## Span evidence is shown only for a callback whose spans were recorded validly
## in a capture whose span family is complete.
spans_absence : Capture.Opened, Capture.Inspected -> [Shown, Absent(Str)]
spans_absence = |opened, inspected| if !Capture.complete(opened, "roc_work_spans") {
	Absent(Capture.absence(opened, "roc_work_spans"))
} else if !inspected.roc_work_valid {
	Absent("roc_work_valid = 0: this callback's work spans were invalid or incomplete")
} else {
	Shown
}

waterfall : Capture.Opened, Capture.Inspected -> List(Gui.Elem(Observatory.State))
waterfall = |opened, inspected| {
	cycle = inspected.cycle
	parts = Capture.decompose(inspected)
	whole = cycle.duration
	row = |name, depth, part, offset, color| waterfall_row({ name, depth, part, offset, whole, color })
	span_rows = match spans_absence(opened, inspected) {
		Absent(reason) => [waterfall_absent({ name: "spans", depth: 2, family: "roc_work_spans", reason })]
		Shown => {
			var $offset = 0
			var $drawn = []
			for kind in Capture.span_kinds {
				duration = match Capture.span(inspected, kind) {
					Found(found) => found.duration
					Missing => 0
				}
				$drawn = $drawn.append(row(kind, 2, duration, $offset, Theme.span))
				$offset = $offset + duration
			}
			$drawn.append(row("unattributed", 2, parts.callback_rest, parts.spans_total, Theme.unattributed))
		}
	}
	apply_at = cycle.callback + cycle.validate
	gpui_rows = match inspected.gpui_apply {
		Some(gpui) => [
			row("gpui apply", 2, gpui, apply_at + inspected.graph_apply, Theme.apply),
			match parts.apply_rest {
				Some(rest) => row("unattributed", 2, rest, apply_at + inspected.graph_apply + gpui, Theme.unattributed)
				None => waterfall_absent({ name: "unattributed", depth: 2, family: "gpui_application", reason: Capture.absence(opened, "gpui_application") })
			},
		]
		None => [
			waterfall_absent({ name: "gpui apply", depth: 2, family: "gpui_application", reason: Capture.absence(opened, "gpui_application") }),
		]
	}
	check = if parts.balanced {
		"✓ Σ parts = ${Format.ms(parts.sum)} = cycle"
	} else {
		"✗ Σ parts = ${Format.ms(parts.sum)}, cycle ${Format.ms(cycle.duration)}: a part exceeds the time that contains it"
	}
	[
		row("cycle", 0, cycle.duration, 0, Theme.ink),
		row("roc callback", 1, cycle.callback, 0, Theme.callback),
	]
		.concat(span_rows)
		.concat(
			[
				row("validate", 1, cycle.validate, cycle.callback, Theme.validate),
				row("apply", 1, cycle.apply, apply_at, Theme.apply),
				row("graph apply", 2, inspected.graph_apply, apply_at, Theme.apply),
			],
		)
		.concat(gpui_rows)
		.concat(
			[
				row("unattributed", 1, parts.cycle_rest, apply_at + cycle.apply, Theme.unattributed),
				Gui.row(
					{ label: "Sum check", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, fg: if parts.balanced Theme.good else Theme.alarm_ink, font_size: Theme.body, font_face: Theme.face },
					[Gui.text(check)],
				),
			],
		)
}

## US-14: every kind, `—` when the cycle has no component work observation.
component_work : Capture.Opened, Capture.Inspected -> List(Gui.Elem(Observatory.State))
component_work = |opened, inspected| {
	absent = if !Capture.complete(opened, "component_work") {
		Some(Capture.absence(opened, "component_work"))
	} else if !inspected.component_work_recorded {
		Some("component_work_recorded = 0: this cycle has no component work observation")
	} else {
		None
	}
	value = |kind| match absent {
		Some(_) => None
		None => Capture.work_count(inspected, kind)
	}
	rows = Capture.work_kinds.map_with_index(
		|name, index| labelled_row("Work ${name}", [
			cell(name, 190, Theme.ink),
			match value(index.to_i64_wrap()) {
				Some(count) => figure_cell(count.to_str(), 70)
				None => dash_cell("component_work", 70)
			},
			rest_cell("", Theme.dim),
		]),
	)
	skip = match (value(2), value(1)) {
		(Some(skipped), Some(compared)) => "skip rate ${Format.percent(skipped, compared)} · ${skipped.to_str()} skipped of ${compared.to_str()} compared"
		_ => "skip rate —"
	}
	reason = match absent {
		Some(why) => [absence_line("component_work", why)]
		None => []
	}
	[heading("COMPONENT WORK")]
		.concat(reason)
		.concat([table("Component work", [table_head("Component work columns", [head_cell("kind", 190), head_figure("count", 70), head_rest("")])].concat(rows)), note(skip)])
}

## US-15
graph_work : Capture.Opened, Capture.Inspected -> List(Gui.Elem(Observatory.State))
graph_work = |opened, inspected| {
	present = Capture.complete(opened, "patch_accounting")
	counter_row = |counter| labelled_row("Graph ${counter.name}", [cell(counter.name, 190, Theme.ink), family_cell(present, "patch_accounting", counter.value.to_str(), 70), rest_cell("", Theme.dim)])
	reason = if present [] else [absence_note(opened, "patch_accounting")]
	[heading("GRAPH WORK")]
		.concat(reason)
		.concat(
			[
				table(
					"Graph work",
					[table_head("Graph work columns", [head_cell("counter", 190), head_figure("count", 70), head_rest("")])]
						.concat(inspected.graph.map(counter_row))
						.concat(inspected.keyed.map(counter_row)),
				),
			],
		)
}

## US-16
span_allocations : Capture.Opened, Capture.Inspected -> List(Gui.Elem(Observatory.State))
span_allocations = |opened, inspected| {
	shown = spans_absence(opened, inspected)
	figures = |kind| match (shown, Capture.span(inspected, kind)) {
		(Shown, Found(found)) => [
			figure_cell(found.alloc_calls.to_str(), 80),
			figure_cell(Format.bytes(found.allocated_bytes), 100),
			figure_cell(found.dealloc_calls.to_str(), 80),
			figure_cell(found.realloc_calls.to_str(), 80),
			figure_cell(Format.bytes(found.reallocated_bytes), 100),
		]
		(Shown, Missing) => [figure_cell("0", 80), figure_cell(Format.bytes(0), 100), figure_cell("0", 80), figure_cell("0", 80), figure_cell(Format.bytes(0), 100)]
		(Absent(_), _) => [dash_cell("roc_work_spans", 80), dash_cell("roc_work_spans", 100), dash_cell("roc_work_spans", 80), dash_cell("roc_work_spans", 80), dash_cell("roc_work_spans", 100)]
	}
	reason = match shown {
		Absent(why) => [absence_line("roc_work_spans", why)]
		Shown => []
	}
	[heading("ALLOCATIONS BY SPAN")]
		.concat(reason)
		.concat(
			[
				table(
					"Allocations",
					[table_head("Allocation columns", [head_cell("span", 190), head_figure("allocs", 80), head_figure("bytes", 100), head_figure("deallocs", 80), head_figure("reallocs", 80), head_figure("realloc bytes", 100), head_rest("")])].concat(
						Capture.span_kinds.map(|kind| labelled_row("Allocation ${kind}", [cell(kind, 190, Theme.ink)].concat(figures(kind)).append(rest_cell("", Theme.dim)))),
					),
				),
			],
		)
}

inspector : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
inspector = |state, opened| match state.inspected {
	None => [note("Press a cycle to inspect it.")]
	Some(inspected) => {
		cycle = inspected.cycle
		step = match (cycle.step_ordinal, inspected.step_line) {
			(Some(ordinal), Some(source_line)) => [
				key({ caption: "Show step ▸ line ${source_line.to_str()}", label: "Show step", selected: False, on_press: |current, _| Observatory.ask(current, ShowStep(cycle.run_id, ordinal)) }),
			]
			_ => []
		}
		title = Gui.row(
			{ label: "Inspector title", width: Fill, padding: 0, gap: Theme.inset, align: Center },
			[
				Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("CYCLE ${cycle_name(cycle)} · ${cycle.trigger} · ${cycle.patch_kind} · ${cycle.phase}")]),
				Gui.row({ padding: 0, gap: Theme.inset, grow: True, justify: End }, step.append(key({ caption: "Close", label: "Close inspector", selected: False, on_press: |current, _| Gui.delegate(Observatory.close_inspector(current)) }))),
			],
		)
		timing = if Capture.complete(opened, "host_cycles") {
			[table("Waterfall", waterfall(opened, inspected))]
		} else {
			[absence_note(opened, "host_cycles")]
		}
		[
			Gui.col(
				{ label: "Cycle inspector", width: Fill, padding: Theme.inset, gap: 6, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				[title, heading("WATERFALL")]
					.concat(timing)
					.concat(
						[
							Gui.row(
								{ label: "Cycle work", width: Fill, padding: 0, gap: Theme.inset },
								[
									Gui.col({ width: Px(300), padding: 0, gap: 4 }, component_work(opened, inspected)),
									Gui.col({ width: Px(300), padding: 0, gap: 4 }, graph_work(opened, inspected)),
								],
							),
						],
					)
					.concat(span_allocations(opened, inspected)),
			),
		]
	}
}

## A part of a view, laid out with the view's own spacing.
section : (Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))) -> (Observatory.State -> Gui.Elem(Observatory.State))
section = |parts| |current| with_capture(current, |state, opened| Gui.col({ width: Fill, padding: 0, gap: Theme.inset }, parts(state, opened)))

## The triggers table, the cycle list, and the inspector are boundaries of their
## own: choosing a trigger renders the table and the list, opening a cycle the
## list's changed rows and the inspector, and sorting only the table.
interactions : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
interactions = |state, _opened| Gui.col(
	{ label: "Interactions", width: Fill, padding: Theme.inset, gap: Theme.inset },
	[
		phase_selector(state, |current, phase| Observatory.ask(current, SetPhase(phase))),
		part_boundary(
			"Triggers",
			|a, b| same_capture(a, b) and a.phase == b.phase and a.trigger_sort == b.trigger_sort and a.filter == b.filter,
			section(triggers_table),
		),
		part_boundary(
			"Cycles",
			|a, b| same_capture(a, b) and a.phase == b.phase and a.filter == b.filter and inspected_id(a) == inspected_id(b) and same_cycles(a, b),
			section(cycles_section),
		),
		heading("CYCLE"),
		part_boundary(
			"Inspector",
			|a, b| same_capture(a, b) and a.inspected == b.inspected,
			section(inspector),
		),
	],
)

## Memory (US-27, US-28)

allocations_by_trigger : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
allocations_by_trigger = |state, opened| {
	present = Capture.complete(opened, "roc_work_spans")
	rows = opened.allocations.keep_if(|found| found.phase == state.phase)
	body = if !present {
		[]
	} else if rows.is_empty() {
		[table_row([rest_cell("No ${state.phase} cycles with valid spans.", Theme.dim)])]
	} else {
		rows.map(
			|found| labelled_row("Allocation ${found.trigger} ${found.span}", [
				cell(found.trigger, 130, Theme.ink),
				cell(found.span, 180, Theme.dim),
				figure_cell(found.cycles.to_str(), 60),
				figure_cell(found.calls_mean.to_str(), 70),
				figure_cell(found.calls_max.to_str(), 70),
				figure_cell(found.calls_total.to_str(), 80),
				figure_cell(Format.bytes(found.bytes_mean), 90),
				figure_cell(Format.bytes(found.bytes_max), 90),
				figure_cell(Format.bytes(found.bytes_total), 90),
				rest_cell("", Theme.dim),
			]),
		)
	}
	reason = if present [] else [absence_note(opened, "roc_work_spans")]
	[heading("ALLOCATIONS BY TRIGGER · ${state.phase} · per cycle with valid spans · warmups excluded")]
		.concat(reason)
		.concat(
			[
				table(
					"Allocations by trigger",
					[
						table_head(
							"Allocation by trigger columns",
							[head_cell("trigger", 130), head_cell("span", 180), head_figure("cycles", 60), head_figure("calls x̄", 70), head_figure("max", 70), head_figure("total", 80), head_figure("bytes x̄", 90), head_figure("max", 90), head_figure("total", 90), head_rest("")],
						),
					].concat(body),
				),
			],
		)
}

## A value that exists only once its run has ended.
ended : Bool, Str, [None, Some(I64)], (I64 -> Str), U32 -> Gui.Elem(Observatory.State)
ended = |present, family_name, value, shape, width| match value {
	Some(number) if present => figure_cell(shape(number), width)
	_ => dash_cell(family_name, width)
}

## Runs recorded without an end snapshot, such as an interactive session's run,
## which has no end until its process exits. Their changes are absent.
unended_note : Capture.Opened, Str -> List(Gui.Elem(Observatory.State))
unended_note = |opened, family_name| {
	unended = opened.resources.keep_if(|found| found.cpu_user == None)
	if unended.is_empty() {
		[]
	} else {
		runs = Str.join_with(unended.map(|found| found.run_id.to_str()), ", ")
		[absence_line(family_name, "no end snapshot was recorded for run ${runs}, so its changes are absent")]
	}
}

count_text : I64 -> Str
count_text = |number| number.to_str()

run_cells : Capture.Resources -> List(Gui.Elem(Observatory.State))
run_cells = |found| [figure_cell(found.run_id.to_str(), 50), cell(found.phase, 90, Theme.ink), figure_cell(Format.maybe_int(found.sample), 60)]

run_lifecycle : Capture.Opened -> List(Gui.Elem(Observatory.State))
run_lifecycle = |opened| {
	present = Capture.complete(opened, "roc_allocations")
	family_name = "roc_allocations"
	rows = opened.resources.map(
		|found| labelled_row(
			"Lifecycle run ${found.run_id.to_str()}",
			run_cells(found)
				.concat(
					[
						ended(present, family_name, found.alloc_calls, count_text, 90),
						ended(present, family_name, found.alloc_bytes, Format.bytes, 100),
						ended(present, family_name, found.dealloc_calls, count_text, 90),
						ended(present, family_name, found.realloc_calls, count_text, 90),
						ended(present, family_name, found.realloc_bytes, Format.bytes, 100),
						rest_cell("", Theme.dim),
					],
				),
		),
	)
	reason = if present unended_note(opened, family_name) else [absence_note(opened, family_name)]
	[heading("RUN LIFECYCLE · Roc allocations from each run's start to its end")]
		.concat(reason)
		.concat(
			[
				table(
					"Run lifecycle",
					[table_head("Run lifecycle columns", [head_figure("run", 50), head_cell("phase", 90), head_figure("index", 60), head_figure("allocs", 90), head_figure("bytes", 100), head_figure("deallocs", 90), head_figure("reallocs", 90), head_figure("realloc bytes", 100), head_rest("")])].concat(rows),
				),
			],
		)
}

process_resources : Capture.Opened -> List(Gui.Elem(Observatory.State))
process_resources = |opened| {
	present = Capture.complete(opened, "process_resources")
	family_name = "process_resources"
	rows = opened.resources.map(
		|found| labelled_row(
			"Resources run ${found.run_id.to_str()}",
			run_cells(found)
				.concat(
					[
						ended(present, family_name, found.cpu_user, Format.ms, 110),
						ended(present, family_name, found.cpu_system, Format.ms, 110),
						ended(present, family_name, found.peak_rss, Format.bytes, 100),
						ended(present, family_name, found.current_rss, Format.bytes, 100),
						rest_cell("", Theme.dim),
					],
				),
		),
	)
	peaks = opened.resources.fold(0, |most, found| match found.peak_rss {
		Some(bytes) if bytes > most => bytes
		_ => most
	})
	chart_row = |found| Gui.row(
		{ label: "RSS run ${found.run_id.to_str()}", width: Fill, height: Px(18), padding: 0, gap: Theme.inset, align: Center },
		[
			cell("${found.phase} ${Format.maybe_int(found.sample)}", 120, Theme.dim),
			match found.peak_rss {
				Some(bytes) if present => Gui.row({ width: Px(bar_span), padding: 0, gap: 0, align: Center }, [block(scaled(bytes, peaks, bar_span), Theme.callback)])
				_ => Gui.row({ width: Px(bar_span), padding: 0, gap: 0, align: Center }, [dash(family_name, Theme.meta)])
			},
			ended(present, family_name, found.peak_rss, Format.bytes, 100),
		],
	)
	reason = if present unended_note(opened, family_name) else [absence_note(opened, family_name)]
	[heading("PROCESS RESOURCES · CPU and RSS from each run's start to its end")]
		.concat(reason)
		.concat(
			[
				table(
					"Process resources",
					[table_head("Process resource columns", [head_figure("run", 50), head_cell("phase", 90), head_figure("index", 60), head_figure("user CPU", 110), head_figure("system CPU", 110), head_figure("peak RSS", 100), head_figure("current RSS", 100), head_rest("")])].concat(rows),
				),
				heading("PEAK RSS BY RUN"),
				Gui.col({ label: "RSS chart", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius }, opened.resources.map(chart_row)),
			],
		)
}

memory : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
memory = |state, opened| Gui.col(
	{ label: "Memory", width: Fill, padding: Theme.inset, gap: Theme.inset },
	[phase_selector(state, |current, phase| Gui.update(Observatory.set_phase(current, phase)))]
		.concat(allocations_by_trigger(state, opened))
		.concat(run_lifecycle(opened))
		.concat(process_resources(opened)),
)

## Spec results (US-21)

run_caption : Capture.Run -> Str
run_caption = |run| {
	index = match run.sample {
		Some(sample) => " ${sample.to_str()}"
		None => ""
	}
	mark = if run.outcome == "pass" "✓" else if run.outcome == "fail" "✗" else "…"
	"${mark} ${run.phase}${index}"
}

step_result : Capture.Step -> Str
step_result = |step| {
	count = match (step.expected_count, step.observed_count) {
		(Some(expected), observed) => ["count ${expected.to_str()} / ${Format.maybe_int(observed)}"]
		(None, Some(observed)) => ["observed ${observed.to_str()}"]
		_ => []
	}
	patch = if Str.is_empty(step.expected_patch) [] else ["patch ${step.expected_patch} / ${step.observed_patch}"]
	diagnostic = if Str.is_empty(step.diagnostic) [] else [step.diagnostic]
	Str.join_with(count.concat(patch).concat(diagnostic), " · ")
}

spec : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
spec = |state, opened| {
	timed = Capture.complete(opened, "step_results")
	selector = Gui.row(
		{ label: "Run", width: Fill, padding: 0, gap: 6, align: Center },
		[meta("RUN")].concat(opened.runs.map(|run| key({ caption: run_caption(run), label: "Run ${run.id.to_str()}", selected: state.run == run.id, on_press: |current, _| Observatory.ask(current, SelectRun(run.id)) }))),
	)
	runs = table(
		"Runs",
		[table_head("Run columns", [head_figure("run", 50), head_cell("phase", 90), head_figure("index", 60), head_cell("outcome", 80), head_figure("steps", 60), head_figure("failed", 60), head_rest("diagnostic")])].concat(
			opened.runs.map(
				|run| table_row([
					figure_cell(run.id.to_str(), 50),
					cell(run.phase, 90, Theme.ink),
					figure_cell(Format.maybe_int(run.sample), 60),
					cell(run.outcome, 80, if run.outcome == "pass" Theme.good else Theme.alarm_ink),
					figure_cell(run.steps.to_str(), 60),
					figure_cell(run.failed.to_str(), 60),
					rest_cell(run.diagnostic, Theme.alarm_ink),
				]),
			),
		),
	)
	window = state.steps.window
	count = Observatory.run_step_count(state)
	# Only the steps near the viewport are built, and only their page is read.
	step_row : U64 -> Gui.Elem(Observatory.State)
	step_row = |index| match Observatory.row_at(window, index) {
		Some(step) => family_row(state.step_focus == Some(step.ordinal), [
			cell("Step line ${step.line.to_str()}", 120, Theme.dim),
			cell(step.kind, 200, Theme.ink),
			cell(step.role, 90, Theme.dim),
			cell(step.status, 50, if step.status == "pass" Theme.good else Theme.alarm_ink),
			if timed figure_cell(Format.maybe_ms(step.duration), 110) else dash_cell("step_results", 110),
			rest_cell(step_result(step), if step.status == "pass" Theme.dim else Theme.alarm_ink),
		])
		None => family_row(False, [cell("…", 120, Theme.dim), rest_cell("reading", Theme.dim)])
	}
	absence = if timed [] else [absence_note(opened, "step_results")]
	focus = match state.step_focus {
		None => []
		Some(ordinal) => {
			found = window.rows.keep_if(|step| step.ordinal == ordinal)
			[
				Gui.panel(
					{ label: "Focused step", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.selected, border_color: Theme.edge, border_width: 1, radius: Theme.radius },
					if found.is_empty() {
						[line("No step of run ${state.run.to_str()} has ordinal ${ordinal.to_str()}.")]
					} else {
						found.map(|step| line(Str.join_with(["line ${step.line.to_str()}", step.kind, step.role, step.status, step_result(step)].keep_if(|part| !Str.is_empty(part)), " · ")))
					},
				),
			]
		}
	}
	Gui.col(
		{ label: "Spec", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset },
		[selector, heading("RUNS"), runs, heading("STEPS OF RUN ${state.run.to_str()} · ${count.to_str()}")]
			.concat(absence)
			.concat(focus)
			.concat(
				[
					Gui.col(
						{ label: "Step table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
						[
							table_head("Step columns", [head_cell("line", 120), head_cell("kind", 200), head_cell("role", 90), head_cell("status", 50), head_figure("duration", 110), head_rest("expected / observed · diagnostic")]),
							Gui.virtual_rows({
								label: "Steps",
								row_height: Theme.row_height,
								count,
								render_row: step_row,
								scroll_to: state.step_scroll,
								on_range: Some(
									|current, visible| match Observatory.steps_wanted(current, visible) {
										Some(offset) => Observatory.ask(current, ReadSteps(offset))
										None => Gui.none
									},
								),
							}),
						],
					),
				],
			),
	)
}

## Health (W9, US-8)

status_ink : Str -> Gui.Color
status_ink = |status| match status {
	"complete" => Theme.good
	"partial" => Theme.caution
	"unfinalized" => Theme.alarm_ink
	_ => Theme.dim
}

flag : I64 -> Str
flag = |value| if value == 0 "ok" else "failed"

## A family row, marked when a `—` elsewhere opened Health at it.
family_row : Bool, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
family_row = |focused, cells| Gui.row(
	{ width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: if focused Theme.selected else Theme.card, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

## The family a `—` opened Health at, with its status and reason in full.
family_focus : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
family_focus = |state, opened| match state.family_focus {
	None => []
	Some(name) => [
		Gui.panel(
			{ label: "Focused family", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.selected, border_color: Theme.edge, border_width: 1, radius: Theme.radius },
			match Capture.family(opened, name) {
				Found(found) => [
					Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("${found.name} · ${found.status}")]),
					Gui.row({ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(found.reason)]),
				]
				Missing => [Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body }, [Gui.text("${name} is not recorded in this capture")])]
			},
		),
	]
}

health : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
health = |state, opened| {
	focused = |name| state.family_focus == Some(name)
	families = table(
		"Measurement families",
		[table_head("Family columns", [head_cell("family", 230), head_cell("detail", 80), head_cell("status", 110), head_figure("rows", 70), head_figure("omitted", 80), head_rest("reason")])].concat(
			opened.families.map(
				|found| family_row(focused(found.name), [
					cell(found.name, 230, Theme.ink),
					cell(found.detail, 80, Theme.dim),
					cell(found.status, 110, status_ink(found.status)),
					figure_cell(found.rows.to_str(), 70),
					figure_cell(found.omitted.to_str(), 80),
					rest_cell(found.reason, Theme.dim),
				]),
			),
		),
	)
	gaps = table(
		"Recording gaps",
		if opened.gaps.is_empty() {
			[table_row([rest_cell("none", Theme.good)])]
		} else {
			[table_head("Gap columns", [head_cell("family", 230), head_figure("lost", 80), head_rest("reason")])].concat(
				opened.gaps.map(|gap| table_row([cell(gap.family, 230, Theme.ink), figure_cell(gap.lost.to_str(), 80), rest_cell(gap.reason, Theme.dim)])),
			)
		},
	)
	recorder = match opened.health {
		Some(found) => [
			line("transactions ${found.transactions.to_str()} · queue high water ${found.queue_high_water.to_str()} · output ${Format.bytes(found.output_bytes)} · rows ${found.rows_written.to_str()}"),
			line("omitted events ${found.omitted_events.to_str()} · writer ${flag(found.writer_failed)} · output limit ${if found.output_limited == 0 "not reached" else "reached"} · drain ${Format.ms(found.drain_ns)}"),
		]
		None => [line("The recorder health row is missing.")]
	}
	unavailable = Capture.metadata(opened, "unavailable_sources")
	Gui.col(
		{ label: "Health", width: Fill, padding: Theme.inset, gap: 6 },
		[
			Gui.row(
				{ label: "Verdict", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[meta("VERDICT"), Gui.row({ padding: 0, gap: 0, fg: verdict_ink(opened.verdict), font_size: Theme.body, font_face: Theme.face }, [Gui.text(Capture.verdict_word(opened.verdict))]), line(Capture.verdict_reason(opened.verdict))],
			),
			note(Capture.rule),
			Gui.col({ label: "Family focus", width: Fill, padding: 0, gap: 0 }, family_focus(state, opened)),
			heading("MEASUREMENT FAMILIES"),
			families,
			heading("RECORDING GAPS"),
			gaps,
			heading("RECORDER HEALTH"),
			Gui.panel({ label: "Recorder health", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius }, recorder),
			heading("IDENTITY · ${opened.metadata.len().to_str()} keys"),
			Gui.panel(
				{ label: "Identity", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				opened.metadata.map(|entry| line("${entry.key} = ${entry.value}")),
			),
			heading("UNAVAILABLE SOURCES"),
			Gui.col(
				{ label: "Unavailable sources", width: Fill, padding: 0, gap: 2 },
				if Str.is_empty(unavailable) [note("none declared")] else Str.split_on(unavailable, ",").map(|source| line(source)),
			),
		],
	)
}

scrolled : Str, Gui.Elem(Observatory.State) -> Gui.Elem(Observatory.State)
scrolled = |label, content| Gui.scroll({ label, content, width: Fill, height: Fill, grow: True })

## Each view compares the capture's revision and the navigation it reads.
main_view : Observatory.State -> Gui.Elem(Observatory.State)
main_view = |state| match state.view {
	Overview => view_boundary("Overview", |a, b| same_capture(a, b) and a.phase == b.phase, |current| with_capture(current, |s, o| scrolled("Overview scroll", overview(s, o))))
	Interactions => view_boundary(
		"Interactions",
		|a, b| same_capture(a, b) and a.phase == b.phase and a.trigger_sort == b.trigger_sort and a.filter == b.filter and a.inspected == b.inspected and same_cycles(a, b),
		|current| with_capture(current, |s, o| scrolled("Interactions scroll", interactions(s, o))),
	)
	Spec => view_boundary("Spec", |a, b| same_capture(a, b) and a.run == b.run and a.step_focus == b.step_focus and a.steps.window.read == b.steps.window.read and a.step_scroll == b.step_scroll, |current| with_capture(current, spec))
	Memory => view_boundary("Memory", |a, b| same_capture(a, b) and a.phase == b.phase, |current| with_capture(current, |s, o| scrolled("Memory scroll", memory(s, o))))
	Health => view_boundary("Health", |a, b| same_capture(a, b) and a.family_focus == b.family_focus, |current| with_capture(current, |s, o| scrolled("Health scroll", health(s, o))))
}

workspace : Observatory.State -> Gui.Elem(Observatory.State)
workspace = |state| Gui.col(
	{ label: "Capture", width: Fill, height: Fill, grow: True, min_height: Px(0), overflow_y: Clip, padding: 0, gap: 0 },
	[
		view_boundary("Capture bar", same_capture, |current| with_capture(current, |_, opened| capture_bar(opened))),
		view_boundary("Trust banner", same_capture, |current| with_capture(current, |_, opened| banner(opened))),
		Gui.row(
			{ label: "Workspace", width: Fill, height: Fill, grow: True, min_height: Px(0), overflow_y: Clip, padding: 0, gap: 0, bg: Theme.paper },
			[view_boundary("Views", |a, b| a.view == b.view, nav), main_view(state)],
		),
	],
)

render : Observatory.State -> Gui.Elem(Observatory.State)
render = |state| Gui.col(
	{ label: "Observatory", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.paper, fg: Theme.ink, font_size: Theme.body },
	[
		header(state),
		authority_bar(state),
		error_band(state),
		match state.capture {
			Some(_) => workspace(state)
			None => view_boundary("Capture list", |a, b| folder_revision(a.folder) == folder_revision(b.folder) and a.capture_sort == b.capture_sort, capture_list)
		},
	],
)
