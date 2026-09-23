## The mounted instrument: a header, the folder authority, the capture list, and
## for an open capture its bar, health banner, view rail, and the chosen view.
## Every figure is drawn from a measurement family; a family that is not
## `complete` is drawn as `—` with its status and reason beside it.
import pf.Gui
import Capture
import Compare
import CompareView
import CopyView
import Format
import Observatory
import PaletteView
import ScalingView
import SourceView
import Theme
import TimelineView
import Widgets

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
note = |caption| Gui.col(
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
	Withheld(_) => Theme.caution
}

verdict_badge : Capture.Verdict -> Str
verdict_badge = |verdict| match verdict {
	Complete => "✓ complete"
	Partial(_) => "⚠ partial"
	Untrusted(_) => "✗ untrusted"
	Unsupported(reason) => "✗ ${reason}"
	Withheld(_) => "… withheld"
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

## An absent value. It is a `—`, never a zero. Hovering it shows why: its
## family, the family's status, and the reason. Pressing it opens Health at
## the family.
dash : Str, Str, U32 -> Gui.Elem(Observatory.State)
dash = |family_name, why, font_size| Gui.tooltip(
	Gui.button({
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
	}),
	why,
)

dash_cell : Str, Str, U32 -> Gui.Elem(Observatory.State)
dash_cell = |family_name, why, width| column_cell({ width, justify: End, ink: Theme.ink, size: Theme.body }, [dash(family_name, why, Theme.body)])

## A figure from one family: its text when the family is complete, otherwise a
## `—` that shows why and opens Health at the family.
family_cell : Capture.Opened, Str, Str, U32 -> Gui.Elem(Observatory.State)
family_cell = |opened, family_name, text, width| if Capture.complete(opened, family_name) figure_cell(text, width) else dash_cell(family_name, Capture.absence(opened, family_name), width)

## The line beside a table whose values are absent.
absence_note : Capture.Opened, Str -> Gui.Elem(Observatory.State)
absence_note = |opened, family_name| absence_line(family_name, Capture.absence(opened, family_name))

absence_line : Str, Str -> Gui.Elem(Observatory.State)
absence_line = |family_name, reason| Gui.row(
	{ label: "Absent ${family_name}", width: Fill, padding: 0, gap: 6, align: Center, fg: Theme.dim, font_size: Theme.meta },
	[dash(family_name, reason, Theme.meta), Gui.text(reason)],
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
	copied = match state.copied {
		Some(done) => [Gui.row({ label: "Copied", padding: 0, gap: 0, fg: Theme.good, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(done)])]
		None => []
	}
	Gui.row(
		{ label: "Observatory header", width: Fill, padding: Theme.inset, gap: 8, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1), fg: Theme.ink, font_size: Theme.meta },
		[
			Gui.text("OBSERVATORY"),
			meta("roc-gui captures, schema ${Capture.supported_schema}, read only"),
			travel("◀ Back", "Back", Observatory.can_go_back(state), Back),
			travel("Forward ▶", "Forward", Observatory.can_go_forward(state), Forward),
			meta("Ctrl+K commands"),
		]
			.concat(copied)
			.append(Gui.row({ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(right)])),
	)
}

## Back and forward over jumps (US-36), each enabled while it has somewhere
## to go.
travel : Str, Str, Bool, Observatory.Request -> Gui.Elem(Observatory.State)
travel = |caption, label, enabled, request| Gui.button({
	caption,
	label,
	enabled,
	on_press: |current, _| Observatory.fulfil({ ..current, request: Some(request) }),
	padding: 2,
	font_size: Theme.meta,
	font_face: Theme.face,
	radius: Theme.radius,
	bg: Theme.card,
	hover_bg: Theme.quiet_hover,
	active_bg: Theme.quiet_active,
	disabled_bg: Theme.rail,
	disabled_fg: Theme.edge,
	fg: Theme.ink,
	border_color: Theme.line,
	border_width: 1,
})

## US-38 anywhere in the window: the palette, back and forward, and a view for
## each of Ctrl+1 to Ctrl+9 in the rail's order.
window_keys : List(Gui.Shortcut(Observatory.State))
window_keys = [
	{ keys: "secondary-k", on_press: |current, _| Gui.update(Observatory.open_palette(current)) },
	{ keys: "alt-left", on_press: |current, _| Observatory.fulfil({ ..current, request: Some(Back) }) },
	{ keys: "alt-right", on_press: |current, _| Observatory.fulfil({ ..current, request: Some(Forward) }) },
]
	.concat(Observatory.views.map_with_index(|view, index| { keys: "secondary-${(index + 1).to_str()}", on_press: |current, _| show_view(current, view) }))

show_view : Observatory.State, Observatory.View -> Gui.Action(Observatory.State)
show_view = |current, view| match current.capture {
	Some(_) => Observatory.fulfil({ ..current, request: Some(Show(view)) })
	None => Gui.none
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

## A capture still being written says so, and while it is watched its new rows
## appear as they are committed. A file that now holds another capture offers
## to read it (US-33, US-34).
capture_bar : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
capture_bar = |state, opened| {
	final = Capture.metadata(opened, "final_state")
	live = if Observatory.watching(state) [chip("● live", Theme.accent)] else []
	changed = if state.changed {
		[
			chip("Capture changed", Theme.caution),
			Gui.button({
				caption: "Reload",
				label: "Reload capture",
				on_press: |current, _| Observatory.ask(current, Reload),
				padding: 3,
				font_size: Theme.meta,
				font_face: Theme.face,
				radius: Theme.radius,
				bg: Theme.card,
				hover_bg: Theme.quiet_hover,
				active_bg: Theme.quiet_active,
				fg: Theme.caution,
				border_color: Theme.caution,
				border_width: 1,
			}),
		]
	} else {
		[]
	}
	clean = Capture.metadata(opened, "clean_shutdown")
	gaps = opened.gaps.len()
	Gui.row(
		{ label: "Capture bar", width: Fill, padding: Theme.inset, gap: 6, align: Center, bg: Theme.paper, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		[
			key({ caption: "‹ Captures", label: "Back to captures", selected: False, on_press: |current, _| Observatory.ask(current, CloseCapture) }),
			chip(Capture.metadata(opened, "backend"), Theme.ink),
			chip(Capture.metadata(opened, "effective_detail"), Theme.ink),
			chip("schema ${Capture.metadata(opened, "schema_version")}", Theme.ink),
			chip(if final == "complete" "✓ final" else "Recording", if final == "complete" Theme.good else Theme.caution),
			# Shutdown and recording gaps are written when the recorder finalises,
			# so until then they are not known rather than clean or zero.
			if final != "complete" chip("no shutdown yet", Theme.dim) else chip(if clean == "1" "clean shutdown" else "unclean shutdown", if clean == "1" Theme.good else Theme.alarm_ink),
			if final != "complete" chip("gaps —", Theme.dim) else chip("gaps ${gaps.to_str()}", if gaps == 0 Theme.good else Theme.alarm_ink),
			chip(Capture.metadata(opened, "timing_quality"), if Capture.metadata(opened, "timing_quality") == "isolated" Theme.ink else Theme.caution),
		]
			.concat(live)
			.concat(changed)
			.append(Gui.row({ padding: 0, gap: 0, grow: True, justify: End }, [chip(verdict_badge(opened.verdict), verdict_ink(opened.verdict))])),
	)
}

banner : Capture.Opened -> Gui.Elem(Observatory.State)
banner = |opened| match opened.verdict {
	Untrusted(cause) => Gui.panel(
		{ label: "Untrusted capture", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, fg: Theme.alarm_ink, border_color: Theme.alarm_line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text("Untrusted capture: ${cause}")])],
	)
	Withheld(cause) => Gui.panel(
		{ label: "Capture not yet finalised", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, fg: Theme.caution, border_color: Theme.line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text("Verdicts withheld: ${cause}. Health, comparison, and scaling are judged once the recorder finalises it.")])],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

nav : Observatory.State -> Gui.Elem(Observatory.State)
nav = |state| {
	entry = |caption, view| key({ caption, label: caption, selected: state.view == view, on_press: |current, _| Observatory.ask(current, Show(view)) })
	Gui.col(
		{ label: "Views", width: Px(Theme.nav_width), height: Fill, padding: Theme.inset, gap: 6, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_right: Px(1) },
		[meta("VIEWS"), entry("Overview", Overview), entry("Interactions", Interactions), entry("Frames", Frames), entry("Timeline", Timeline), entry("Spec", Spec), entry("Memory", Memory), entry("Health", Health), entry("Compare", Compare), entry("Scaling", Scaling)],
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
			Gui.row({ padding: 0, gap: 0 }, [dash(props.family, props.detail, Theme.figure)])
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
	spec_name = m("spec_name")
	spec = if Str.is_empty(spec_name) "no specification" else "spec \"${spec_name}\""
	samples = m("benchmark_samples")
	benchmark = if Str.is_empty(spec_name) {
		"interactive session: no test run"
	} else if samples == "0" or Str.is_empty(samples) {
		"not a benchmark: one test run"
	} else {
		"benchmark: ${m("benchmark_warmups")} warmups · ${samples} samples · ${m("benchmark_iterations")} iterations · scale ${m("benchmark_scale")}"
	}
	[
		line("${m("app_name")} · ${spec} · ${m("target_profile")}"),
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
							tile({ name: "Frames over budget", family: "gpui_frame_spans", value: frames.value, detail: frames.detail, opens: "Frames", view: Frames }),
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

## Past the columns above, the order is |Δ| against the baseline, which
## `magnitude` measures.
trigger_key : Capture.Trigger, U64, (Capture.Trigger -> I64) -> SortKey
trigger_key = |trigger, column, magnitude| match column {
	0 => Text(trigger.trigger)
	1 => Text(trigger.patch_kind)
	2 => Number(trigger.count)
	3 => Number(trigger.min)
	4 => Number(trigger.median)
	5 => Number(trigger.max)
	6 => Number(trigger.iqr)
	_ => Number(magnitude(trigger))
}

sorted_triggers : List(Capture.Trigger), Observatory.Sort, (Capture.Trigger -> I64) -> List(Capture.Trigger)
sorted_triggers = |triggers, sort, magnitude| List.sort_with(
	triggers,
	|left, right| {
		order = compare_keys(trigger_key(left, sort.column, magnitude), trigger_key(right, sort.column, magnitude))
		if sort.descending reverse_order(order) else order
	},
)

trigger_heads : Observatory.State -> List(Gui.Elem(Observatory.State))
trigger_heads = |state| trigger_columns
	.map_with_index(
		|column, index| sort_head({
			caption: column.caption,
			label: "Sort triggers by ${column.caption}",
			width: column.width,
			figure: column.figure,
			sort: CompareView.trigger_sort(state),
			column: index,
			on_press: |current| Observatory.sort_triggers(current, index),
		}),
	)
	.concat(CompareView.trigger_heads(state))
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
	shown = |ns, width| family_cell(opened, "host_cycles", Format.ms(ns), width)
	compared = CompareView.mode(state)
	rows = sorted_triggers(opened.triggers.keep_if(|trigger| trigger.phase == state.phase), CompareView.trigger_sort(state), |trigger| Compare.magnitude(Compare.trigger_delta(compared, opened, trigger)))
	body = if rows.is_empty() {
		[note("No cycles were recorded in the ${state.phase} phase.")]
	} else {
		rows.map(
			|trigger| table_row(
				[
					cell(trigger.trigger, 180, Theme.ink),
					cell(trigger.patch_kind, 110, Theme.dim),
					family_cell(opened, "host_cycles", trigger.count.to_str(), 70),
					shown(trigger.min, 110),
					shown(trigger.median, 110),
					shown(trigger.max, 110),
					shown(trigger.iqr, 110),
				]
					.concat(CompareView.trigger_cells(compared, opened, trigger))
					.append(trigger_filter(state, trigger)),
			),
		)
	}
	absence = if timed [] else [absence_note(opened, "host_cycles")]
	sort = CompareView.trigger_sort(state)
	order = if sort.column == Observatory.delta_column "|Δ|" else sort_caption(trigger_columns, sort)
	[CopyView.heading("TRIGGERS · ${state.phase} · by ${order} · warmups excluded", "Triggers", |_| CopyView.triggers(opened, rows))]
		.concat(absence)
		.concat([table("Triggers", [table_head("Trigger columns", trigger_heads(state))].concat(body))])
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
## Whether cycle durations were recorded, and why not when they were not.
Timing : [Timed, Untimed(Str)]

cycle_boundary : Capture.Cycle, I64, Timing -> Gui.Elem(Observatory.State)
cycle_boundary = |cycle, slowest, timing| boundary(
	Gui.Key.id(cycle.id.to_u64_wrap()),
	|a, b| same_capture(a, b) and a.phase == b.phase and a.filter == b.filter and is_chosen(a, cycle.id) == is_chosen(b, cycle.id),
	Observatory.forward,
	|current| cycle_row(is_chosen(current, cycle.id), cycle, slowest, timing),
)

cycle_row : Bool, Capture.Cycle, I64, Timing -> Gui.Elem(Observatory.State)
cycle_row = |chosen, cycle, slowest, timing| {
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
			cell(Capture.target_caption(cycle), 190, Theme.dim),
			cell(cycle.patch_kind, 90, Theme.dim),
			match timing {
				Timed => figure_cell(Format.ms(cycle.duration), 110)
				Untimed(why) => dash_cell("host_cycles", why, 110)
			},
			match timing {
				Timed => stacked_bar(cycle, slowest)
				Untimed(_) => rest_cell("", Theme.dim)
			},
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
	timing = if Capture.complete(opened, "host_cycles") Timed else Untimed(Capture.absence(opened, "host_cycles"))
	window = Observatory.listed_cycles(state)
	total = Observatory.cycle_total(state)
	# The bars share one scale: the slowest cycle of everything listed.
	slowest = Observatory.listed_triggers(state, opened).fold(0, |most, found| if found.max > most found.max else most)
	within_scope = match Observatory.within(state.filter) {
		All => "every trigger"
		Only(chosen) => "${chosen.trigger} · ${chosen.patch_kind}"
	}
	scope = match state.filter {
		InBucket(held) => "${within_scope} · ${range_text(held.bucket)}"
		_ => within_scope
	}
	render_row : U64 -> Gui.Elem(Observatory.State)
	render_row = |index| match Observatory.row_at(window, index) {
		Some(cycle) => cycle_boundary(cycle, slowest, timing)
		None => pending_row(index)
	}
	row_key : U64 -> U64
	row_key = |index| match Observatory.row_at(window, index) {
		Some(cycle) => cycle.id.to_u64_wrap()
		None => pending_key(index)
	}
	clear = match state.filter {
		InBucket(held) => [key({ caption: "All durations", label: "Clear duration bucket", selected: False, on_press: |current, _| Observatory.ask(current, FilterBucket(held.bucket, held.count)) })]
		_ => []
	}
	jumps = if total > 1 {
		[
			key({ caption: "Slowest", label: "Scroll to slowest cycle", selected: False, on_press: |current, _| Observatory.ask(current, JumpToCycle(0, Start)) }),
			key({ caption: "Fastest", label: "Scroll to fastest cycle", selected: False, on_press: |current, _| Observatory.ask(current, JumpToCycle(total - 1, End)) }),
		]
	} else {
		[]
	}
	# The rows the list holds, which are the rows it can show.
	copy = if window.rows.is_empty() [] else [CopyView.copy_key("Cycles", |_| CopyView.cycles(opened, window.rows))]
	body = if total == 0 {
		[note("No ${state.phase} cycles to list.")]
	} else {
		[
			Gui.col(
				{ label: "Cycle table", width: Fill, height: Px(Theme.row_height * 9), padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
				[
					table_head("Cycle columns", [head_cell("cycle", 100), head_cell("trigger", 150), head_cell("target", 190), head_cell("patch", 90), head_figure("duration", 110), head_rest("callback · validate · apply · unattributed")]),
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
				.concat(clear)
				.concat(jumps)
				.concat(copy)
				.append(Gui.row({ padding: 0, gap: 0, grow: True, justify: End }, [legend])),
		),
	]
		.concat(body)
}

## The cycle inspector (W3)

## The width the inspector gives a detail inside its card: the pane's size
## less the pane's and the card's padding and the card's and table's borders.
inspector_content : Observatory.State -> U32
inspector_content = |state| {
	overhead = 2 * Theme.inset + 2 * Theme.inset + 4 + Theme.inset
	if state.inspector.size > overhead + 120 state.inspector.size - overhead else 120
}

## How a waterfall shares the inspector's width: a column of names, one of
## durations, and the rest for the bars, which grow with the inspector up to
## the width they have below a view.
WaterfallColumns : { name : U32, figure : U32, bars : U32 }

waterfall_columns : U32 -> WaterfallColumns
waterfall_columns = |content| {
	figure = 72
	# The row's own left padding and the figure; the name column holds the
	# indent, so the deepest names keep 148 pixels of it.
	fixed = Theme.inset + figure
	names = 180
	room = if content > fixed + names + 40 content - fixed - names else 40
	bars = if room > 420 420 else room
	name = if content > fixed + bars + 64 content - fixed - bars else 64
	{ name, figure, bars }
}

## One waterfall row: a name indented by depth, its duration, and its bar at
## its offset within the cycle.
waterfall_row : { name : Str, depth : U32, part : I64, offset : I64, whole : I64, color : Gui.Color, columns : WaterfallColumns } -> Gui.Elem(Observatory.State)
waterfall_row = |props| Gui.row(
	{ label: "Waterfall ${props.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset + props.depth * 16), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[
		cell(props.name, props.columns.name - props.depth * 16, Theme.ink),
		figure_cell(Format.ms(props.part), props.columns.figure),
		offset_bar({ offset: props.offset, part: props.part, whole: props.whole, span: props.columns.bars, color: props.color }),
	],
)

## A waterfall row whose value is absent: its `—` and why.
waterfall_absent : { name : Str, depth : U32, family : Str, reason : Str, columns : WaterfallColumns } -> Gui.Elem(Observatory.State)
waterfall_absent = |props| Gui.row(
	{ label: "Waterfall ${props.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset + props.depth * 16), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[cell(props.name, props.columns.name - props.depth * 16, Theme.ink), dash_cell(props.family, props.reason, props.columns.figure), rest_cell(props.reason, Theme.dim)],
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

waterfall : Capture.Opened, Capture.Inspected, WaterfallColumns -> List(Gui.Elem(Observatory.State))
waterfall = |opened, inspected, columns| {
	cycle = inspected.cycle
	parts = Capture.decompose(inspected)
	whole = cycle.duration
	row = |name, depth, part, offset, color| waterfall_row({ name, depth, part, offset, whole, color, columns })
	span_rows = match spans_absence(opened, inspected) {
		Absent(reason) => [waterfall_absent({ name: "spans", depth: 2, family: "roc_work_spans", reason, columns })]
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
				None => waterfall_absent({ name: "unattributed", depth: 2, family: "gpui_application", reason: Capture.absence(opened, "gpui_application"), columns })
			},
		]
		None => [
			waterfall_absent({ name: "gpui apply", depth: 2, family: "gpui_application", reason: Capture.absence(opened, "gpui_application"), columns }),
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
component_work : Capture.Opened, Capture.Inspected, U32 -> List(Gui.Elem(Observatory.State))
component_work = |opened, inspected, name_width| {
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
				None => dash_cell(
					"component_work",
					match absent {
						Some(why) => why
						None => Capture.absence(opened, "component_work")
					},
					70,
				)
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
		.concat([table("Component work", [table_head("Component work columns", [head_cell("kind", name_width), head_figure("count", 70), head_rest("")])].concat(rows)), note(skip)])
}

## US-15
graph_work : Capture.Opened, Capture.Inspected, U32 -> List(Gui.Elem(Observatory.State))
graph_work = |opened, inspected, name_width| {
	present = Capture.complete(opened, "patch_accounting")
	counter_row = |counter| labelled_row("Graph ${counter.name}", [cell(counter.name, name_width, Theme.ink), family_cell(opened, "patch_accounting", counter.value.to_str(), 70), rest_cell("", Theme.dim)])
	reason = if present [] else [absence_note(opened, "patch_accounting")]
	[heading("GRAPH WORK")]
		.concat(reason)
		.concat(
			[
				table(
					"Graph work",
					[table_head("Graph work columns", [head_cell("counter", name_width), head_figure("count", 70), head_rest("")])]
						.concat(inspected.graph.map(counter_row))
						.concat(inspected.keyed.map(counter_row)),
				),
			],
		)
}

## US-16. The five figures share one table where the inspector is wide
## enough for them beside a span's name; otherwise a span's allocations, its
## releases, and its reallocations are a table each, so no figure is cut off.
span_allocations : Capture.Opened, Capture.Inspected, U32 -> List(Gui.Elem(Observatory.State))
span_allocations = |opened, inspected, content| {
	shown = spans_absence(opened, inspected)
	whole = [{ index: 0, caption: "allocs", width: 64 }, { index: 1, caption: "bytes", width: 84 }, { index: 2, caption: "deallocs", width: 72 }, { index: 3, caption: "reallocs", width: 72 }, { index: 4, caption: "realloc bytes", width: 104 }]
	tables = if content >= whole.fold(Theme.inset + 150, |total, found| total + found.width) {
		[span_table({ inspected, shown, content, label: "Allocations", row_label: "Allocation", name_head: "span", columns: whole })]
	} else {
		[
			span_table({ inspected, shown, content, label: "Allocations", row_label: "Allocation", name_head: "allocations", columns: [{ index: 0, caption: "calls", width: 56 }, { index: 1, caption: "bytes", width: 84 }] }),
			span_table({ inspected, shown, content, label: "Releases", row_label: "Release", name_head: "releases", columns: [{ index: 2, caption: "calls", width: 56 }] }),
			span_table({ inspected, shown, content, label: "Reallocations", row_label: "Reallocation", name_head: "reallocations", columns: [{ index: 3, caption: "calls", width: 56 }, { index: 4, caption: "bytes", width: 84 }] }),
		]
	}
	reason = match shown {
		Absent(why) => [absence_line("roc_work_spans", why)]
		Shown => []
	}
	[heading("ALLOCATIONS BY SPAN")].concat(reason).concat(tables)
}

## A span's allocation figures, by the index `span_allocations` gives them:
## calls and bytes allocated, calls released, and calls and bytes
## reallocated.
allocation_figure : [Missing, Found(Capture.Span)], U64 -> Str
allocation_figure = |found_span, index| {
	texts = match found_span {
		Found(found) => [found.alloc_calls.to_str(), Format.bytes(found.allocated_bytes), found.dealloc_calls.to_str(), found.realloc_calls.to_str(), Format.bytes(found.reallocated_bytes)]
		Missing => ["0", Format.bytes(0), "0", "0", Format.bytes(0)]
	}
	texts.get(index) ?? ""
}

## Some of a span's allocation figures beside each span's name, which takes
## what they leave of the inspector. A figure is `—` with its reason when the
## spans are absent.
span_table : { inspected : Capture.Inspected, shown : [Shown, Absent(Str)], content : U32, label : Str, row_label : Str, name_head : Str, columns : List({ index : U64, caption : Str, width : U32 }) } -> Gui.Elem(Observatory.State)
span_table = |props| {
	used = props.columns.fold(Theme.inset, |total, found| total + found.width)
	name = if props.content > used + 190 190 else if props.content > used + 40 props.content - used else 40
	figures = |kind| props.columns.map(
		|column| match props.shown {
			Shown => figure_cell(allocation_figure(Capture.span(props.inspected, kind), column.index), column.width)
			Absent(why) => dash_cell("roc_work_spans", why, column.width)
		},
	)
	table(
		props.label,
		[table_head("${props.row_label} columns", [head_cell(props.name_head, name)].concat(props.columns.map(|column| head_figure(column.caption, column.width))).append(head_rest("")))].concat(
			Capture.span_kinds.map(|kind| labelled_row("${props.row_label} ${kind}", [cell(kind, name, Theme.ink)].concat(figures(kind)).append(rest_cell("", Theme.dim)))),
		),
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
		# The title and its keys stack, so a narrow inspector keeps both.
		title = Gui.col(
			{ label: "Inspector title", width: Fill, padding: 0, gap: 6 },
			[
				Gui.col({ width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("CYCLE ${cycle_name(cycle)} · ${cycle.trigger} · ${cycle.patch_kind} · ${cycle.phase}")]),
				Gui.row({ padding: 0, gap: Theme.inset }, step.append(key({ caption: "Close", label: "Close inspector", selected: False, on_press: |current, _| Gui.delegate(Observatory.close_inspector(current)) }))),
			],
		)
		content = inspector_content(state)
		# A counter's name takes what its count leaves, up to the width it has
		# below a view.
		work_name = if content > Theme.inset + 70 + 190 190 else if content > Theme.inset + 70 + 40 content - Theme.inset - 70 else 40
		timed = Capture.complete(opened, "host_cycles")
		timing = if timed {
			[table("Waterfall", waterfall(opened, inspected, waterfall_columns(content)))]
		} else {
			[absence_note(opened, "host_cycles")]
		}
		waterfall_heading = if timed CopyView.heading("WATERFALL", "Waterfall", |_| CopyView.waterfall(opened, inspected, spans_absence(opened, inspected))) else heading("WATERFALL")
		[
			Gui.col(
				{ label: "Cycle inspector", width: Fill, padding: Theme.inset, gap: 6, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				[title, Widgets.labelled_note("Cycle target", "TARGET ${Capture.target_caption(cycle)}", Theme.dim)]
					.concat(CompareView.cycle_line(CompareView.mode(state), opened, cycle))
					.append(waterfall_heading)
					.concat(timing)
					.concat(
						[
							Gui.col(
								{ label: "Cycle work", width: Fill, padding: 0, gap: Theme.inset },
								[
									Gui.col({ width: Fill, padding: 0, gap: 4 }, component_work(opened, inspected, work_name)),
									Gui.col({ width: Fill, padding: 0, gap: 4 }, graph_work(opened, inspected, work_name)),
								],
							),
						],
					)
					.concat(span_allocations(opened, inspected, content)),
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
			|a, b| same_capture(a, b) and a.phase == b.phase and a.trigger_sort == b.trigger_sort and a.filter == b.filter and CompareView.same_comparison(a, b),
			section(triggers_table),
		),
		part_boundary(
			"Distribution",
			|a, b| same_capture(a, b) and a.phase == b.phase and a.filter == b.filter and a.bucket_hover == b.bucket_hover,
			section(distribution),
		),
		part_boundary(
			"Cycles",
			|a, b| same_capture(a, b) and a.phase == b.phase and a.filter == b.filter and inspected_id(a) == inspected_id(b) and same_cycles(a, b),
			section(cycles_section),
		),
	],
)
	.shortcuts(cycle_keys)

## US-38 in Interactions: J and K inspect the next and the previous cycle of
## the list, slowest first, and I moves keyboard focus into the inspector.
cycle_keys : List(Gui.Shortcut(Observatory.State))
cycle_keys = [
	{ keys: "j", on_press: |current, _| Observatory.ask(current, InspectAdjacent(1)) },
	{ keys: "k", on_press: |current, _| Observatory.ask(current, InspectAdjacent(-1)) },
	{ keys: "i", on_press: |current, _| Gui.delegate({ ..current, inspector_focus: current.inspector_focus + 1 }) },
]

## The inspector, which I moves keyboard focus into. Annotated: written as an
## unannotated lambda in place, the pinned compiler overflows its stack.
inspector_part : Observatory.State -> Gui.Elem(Observatory.State)
inspector_part = |current| Gui.request_focus(section(inspector)(current), current.inspector_focus)

## Memory (US-27, US-28)

allocations_by_trigger : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
allocations_by_trigger = |state, opened| {
	present = Capture.complete(opened, "roc_work_spans")
	compared = CompareView.mode(state)
	rows = opened.allocations.keep_if(|found| found.phase == state.phase)
	body = if !present {
		[]
	} else if rows.is_empty() {
		[table_row([rest_cell("No ${state.phase} cycles with valid spans.", Theme.dim)])]
	} else {
		rows.map(
			|found| labelled_row(
				"Allocation ${found.trigger} ${found.span}",
				[
					cell(found.trigger, 130, Theme.ink),
					cell(found.span, 180, Theme.dim),
					figure_cell(found.cycles.to_str(), 60),
					figure_cell(found.calls_mean.to_str(), 70),
					figure_cell(found.calls_max.to_str(), 70),
					figure_cell(found.calls_total.to_str(), 80),
					figure_cell(Format.bytes(found.bytes_mean), 90),
					figure_cell(Format.bytes(found.bytes_max), 90),
					figure_cell(Format.bytes(found.bytes_total), 90),
				]
					.concat(CompareView.allocation_cells(compared, opened, found))
					.append(rest_cell("", Theme.dim)),
			),
		)
	}
	reason = if present [] else [absence_note(opened, "roc_work_spans")]
	[CopyView.heading("ALLOCATIONS BY TRIGGER · ${state.phase} · per cycle with valid spans · warmups excluded", "Allocations by trigger", |_| CopyView.allocations(opened, rows))]
		.concat(reason)
		.concat(
			[
				table(
					"Allocations by trigger",
					[
						table_head(
							"Allocation by trigger columns",
							[head_cell("trigger", 130), head_cell("span", 180), head_figure("cycles", 60), head_figure("calls x̄", 70), head_figure("max", 70), head_figure("total", 80), head_figure("bytes x̄", 90), head_figure("max", 90), head_figure("total", 90)].concat(CompareView.allocation_heads(compared)).append(head_rest("")),
						),
					].concat(body),
				),
			],
		)
}

## A value that exists only once its run has ended.
ended : Capture.Opened, Str, [None, Some(I64)], (I64 -> Str), U32 -> Gui.Elem(Observatory.State)
ended = |opened, family_name, value, shape, width| match value {
	Some(number) if Capture.complete(opened, family_name) => figure_cell(shape(number), width)
	_ => dash_cell(family_name, unended_why(opened, family_name), width)
}

## Why a run's change is absent: its family was not recorded, or the run
## never ended.
unended_why : Capture.Opened, Str -> Str
unended_why = |opened, family_name| if Capture.complete(opened, family_name) "${family_name} complete: no end snapshot was recorded for this run, so its change is absent" else Capture.absence(opened, family_name)

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
						ended(opened, family_name, found.alloc_calls, count_text, 90),
						ended(opened, family_name, found.alloc_bytes, Format.bytes, 100),
						ended(opened, family_name, found.dealloc_calls, count_text, 90),
						ended(opened, family_name, found.realloc_calls, count_text, 90),
						ended(opened, family_name, found.realloc_bytes, Format.bytes, 100),
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
						ended(opened, family_name, found.cpu_user, Format.ms, 110),
						ended(opened, family_name, found.cpu_system, Format.ms, 110),
						ended(opened, family_name, found.peak_rss, Format.bytes, 100),
						ended(opened, family_name, found.current_rss, Format.bytes, 100),
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
				_ => Gui.row({ width: Px(bar_span), padding: 0, gap: 0, align: Center }, [dash(family_name, unended_why(opened, family_name), Theme.meta)])
			},
			ended(opened, family_name, found.peak_rss, Format.bytes, 100),
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
	annotated = Observatory.annotated(state)
	selector = Gui.row(
		{ label: "Run", width: Fill, padding: 0, gap: 6, align: Center },
		[meta("RUN")]
			.concat(opened.runs.map(|run| key({ caption: run_caption(run), label: "Run ${run.id.to_str()}", selected: if annotated SourceView.shows_run(state, run.id) else state.run == run.id, on_press: |current, _| Observatory.ask(current, SelectRun(run.id)) })))
			.concat(SourceView.median_key(state, opened)),
	)
	source_bar = SourceView.bar(state, opened)
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
			if timed figure_cell(Format.maybe_ms(step.duration), 110) else dash_cell("step_results", Capture.absence(opened, "step_results"), 110),
			rest_cell(step_result(step), if step.status == "pass" Theme.dim else Theme.alarm_ink),
		])
		None => family_row(False, [cell("…", 120, Theme.dim), rest_cell("reading", Theme.dim)])
	}
	absence = if timed [] else [absence_note(opened, "step_results")]
	if annotated {
		Gui.col(
			{ label: "Spec", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset },
			[selector].concat(source_bar).concat([SourceView.annotated(state, opened)]),
		)
	} else {
		Gui.col(
			{ label: "Spec", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset },
			[selector].concat(source_bar).concat([heading("RUNS"), runs, CopyView.heading("STEPS OF RUN ${state.run.to_str()} · ${count.to_str()}", "Steps", |_| CopyView.steps(opened, window.rows, step_result))])
				.concat(absence)
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
}

## The step Show step opened, in the selected run.
focused_step : Observatory.State -> List(Gui.Elem(Observatory.State))
focused_step = |state| match state.step_focus {
	None => [note("Press Show step on a cycle, or choose a step, to inspect it.")]
	Some(ordinal) => {
		found = state.steps.window.rows.keep_if(|step| step.ordinal == ordinal)
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
			CopyView.heading("MEASUREMENT FAMILIES", "Measurement families", |_| CopyView.families(opened)),
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

## Charts. A chart is a canvas of integer primitives: bars and rules from the
## capture's figures, captions in canvas text, and a transparent hit rectangle
## over every bar so the whole column, not only its painted height, answers the
## pointer. Captions are never targets, so a readout drawn over a bar leaves
## the bar as the thing under the pointer.

box : { key : U64, label : Str, x : I64, y : I64, width : I64, height : I64, fill : Gui.Color } -> Gui.CanvasPrimitive
box = |props| Gui.rectangle({
	key: props.key,
	label: props.label,
	x: props.x.to_i32_wrap(),
	y: props.y.to_i32_wrap(),
	width: if props.width < 0 0 else props.width.to_u32_wrap(),
	height: if props.height < 0 0 else props.height.to_u32_wrap(),
	fill: props.fill,
})

rule : { key : U64, label : Str, x1 : I64, y1 : I64, x2 : I64, y2 : I64, stroke : Gui.Color } -> Gui.CanvasPrimitive
rule = |props| Gui.line({ key: props.key, label: props.label, x1: props.x1.to_i32_wrap(), y1: props.y1.to_i32_wrap(), x2: props.x2.to_i32_wrap(), y2: props.y2.to_i32_wrap(), stroke: props.stroke, stroke_width: 1 })

caption : { key : U64, label : Str, x : I64, y : I64, width : I64, value : Str, color : Gui.Color, align : Gui.CanvasTextAlign } -> Gui.CanvasPrimitive
caption = |props| Gui.canvas_text({
	key: props.key,
	label: props.label,
	x: props.x.to_i32_wrap(),
	y: props.y.to_i32_wrap(),
	width: props.width.to_u32_wrap(),
	value: props.value,
	color: props.color,
	size: 11,
	align: props.align,
})

## A chart marker's label: it reads rightward from the marker, and leftward
## where reading rightward would leave the plot.
marker_label : { key : U64, label : Str, at : I64, y : I64, value : Str, color : Gui.Color } -> Gui.CanvasPrimitive
marker_label = |props| {
	label_width = 160
	if props.at + 4 + label_width > chart_gutter + chart_plot {
		caption({ key: props.key, label: props.label, x: props.at - 4 - label_width, y: props.y, width: label_width, value: props.value, color: props.color, align: End })
	} else {
		caption({ key: props.key, label: props.label, x: props.at + 4, y: props.y, width: label_width, value: props.value, color: props.color, align: Start })
	}
}

## A part scaled into a span of pixels; any non-zero part is at least one
## pixel.
pixels : I64, I64, I64 -> I64
pixels = |part, whole, span| if whole <= 0 or part <= 0 {
	0
} else {
	scaled_part = part * span / whole
	if scaled_part < 1 1 else scaled_part
}

## A hit target's key names what it stands for: keys from 1 are the columns
## or buckets themselves, and every painted shape's key is offset past them.
target_of : [None, Some(U64)], I64 -> [None, Some(I64)]
target_of = |target, count| match target {
	Some(hit) if hit >= 1 and hit.to_i64_wrap() <= count => Some(hit.to_i64_wrap() - 1)
	_ => None
}

painted : I64, I64 -> U64
painted = |layer, index| (layer * 1000 + index).to_u64_wrap()

## The duration distribution (US-11)

## The cycles of the list's scope counted by octave bucket.
bucket_counts : Observatory.State, Capture.Opened -> List({ bucket : I64, count : I64 })
bucket_counts = |state, opened| {
	scope = Observatory.within(state.filter)
	matching = opened.buckets.keep_if(
		|found| found.phase == state.phase
		and (
			match scope {
				All => True
				Only(chosen) => found.trigger == chosen.trigger and found.patch_kind == chosen.patch_kind
			}
		),
	)
	var $counts = []
	var $bucket = 0
	while $bucket < Capture.bucket_count {
		count = matching.keep_if(|found| found.bucket == $bucket).fold(0, |total, found| total + found.count)
		$counts = $counts.append({ bucket: $bucket, count })
		$bucket = $bucket + 1
	}
	$counts
}

range_text : I64 -> Str
range_text = |bucket| {
	range = Capture.bucket_range(bucket)
	if bucket <= 0 {
		"below ${Format.ms(range.high)}"
	} else if bucket >= Capture.bucket_count - 1 {
		"${Format.ms(range.low)} and above"
	} else {
		"${Format.ms(range.low)} to ${Format.ms(range.high)}"
	}
}

chart_gutter : I64
chart_gutter = 56

chart_plot : I64
chart_plot = 720

## Where a duration falls on the distribution's logarithmic axis, from the
## first shown bucket, each `width` pixels wide.
duration_x : I64, I64, I64 -> I64
duration_x = |duration, first, width| {
	bucket = Capture.bucket_of(duration)
	range = Capture.bucket_range(bucket)
	within_bucket = if range.high - range.low <= 0 or bucket >= Capture.bucket_count - 1 0 else (duration - range.low) * width / (range.high - range.low)
	chart_gutter + (bucket - first) * width + within_bucket
}

distribution : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
distribution = |state, opened| {
	counts = bucket_counts(state, opened)
	held = counts.keep_if(|found| found.count > 0)
	if !Capture.complete(opened, "host_cycles") {
		[heading("DURATION DISTRIBUTION"), absence_note(opened, "host_cycles")]
	} else if held.is_empty() {
		[heading("DURATION DISTRIBUTION"), note("No ${state.phase} cycles to count.")]
	} else {
		first = match held.first() {
			Ok(found) => found.bucket
			Err(_) => 0
		}
		last = match held.last() {
			Ok(found) => found.bucket
			Err(_) => 0
		}
		shown = counts.keep_if(|found| found.bucket >= first and found.bucket <= last)
		width = chart_plot / (last - first + 1)
		tallest = shown.fold(0, |most, found| if found.count > most found.count else most)
		median_row = 18
		max_row = 32
		top = 48
		bottom = 148
		chosen = match state.filter {
			InBucket(held_bucket) => Some(held_bucket.bucket)
			_ => None
		}
		bars = shown.map(
			|found| {
				height = pixels(found.count, tallest, bottom - top)
				fill = if chosen == Some(found.bucket) Theme.accent else if state.bucket_hover == Some(found.bucket) Theme.span else Theme.callback
				box({ key: painted(1, found.bucket), label: "Bucket bar ${range_text(found.bucket)}", x: chart_gutter + (found.bucket - first) * width + 1, y: bottom - height, width: width - 2, height, fill })
			},
		)
		edges = shown.keep_if(|found| (found.bucket - first) % 2 == 0).map(
			|found| caption({ key: painted(2, found.bucket), label: "Bucket edge ${found.bucket.to_str()}", x: chart_gutter + (found.bucket - first) * width - 40, y: bottom + 4, width: 80, value: Format.ms(Capture.bucket_range(found.bucket).low), color: Theme.dim, align: Center }),
		)
		scope = Observatory.within(state.filter)
		listed = Observatory.listed_triggers(state, opened)
		slowest = listed.fold(0, |most, found| if found.max > most found.max else most)
		median = match scope {
			Only(chosen_trigger) => match listed.find_first(|found| found.trigger == chosen_trigger.trigger and found.patch_kind == chosen_trigger.patch_kind) {
				Ok(found) => found.median
				Err(_) => 0
			}
			All => match opened.medians.find_first(|found| found.phase == state.phase) {
				Ok(found) => found.median
				Err(_) => 0
			}
		}
		median_x = duration_x(median, first, width)
		max_x = duration_x(slowest, first, width)
		# Each marker's label has a row of its own above the bars, so the two
		# never meet and neither covers a bar. A label reads rightward from
		# its marker and reads leftward where it would leave the plot.
		markers = [
			rule({ key: painted(3, 1), label: "Median marker", x1: median_x, y1: median_row, x2: median_x, y2: bottom, stroke: Theme.ink }),
			marker_label({ key: painted(3, 2), label: "Median caption", at: median_x, y: median_row, value: "median ${Format.ms(median)}", color: Theme.ink }),
			rule({ key: painted(3, 3), label: "Max marker", x1: max_x, y1: max_row, x2: max_x, y2: bottom, stroke: Theme.alarm_ink }),
			marker_label({ key: painted(3, 4), label: "Max caption", at: max_x, y: max_row, value: "max ${Format.ms(slowest)}", color: Theme.alarm_ink }),
		]
		readout_text = match state.bucket_hover {
			Some(bucket) => {
				count = match counts.get(bucket.to_u64_wrap()) {
					Ok(found) => found.count
					Err(_) => 0
				}
				"${range_text(bucket)} · ${count.to_str()} cycles · press to list them"
			}
			None => "Hover a bucket for its range and count; press it to list its cycles."
		}
		hover_mark = match state.bucket_hover {
			Some(bucket) if bucket >= first and bucket <= last => [box({ key: painted(6, 1), label: "Hovered bucket", x: chart_gutter + (bucket - first) * width, y: top, width, height: bottom - top, fill: Theme.selected })]
			_ => []
		}
		readout = caption({ key: painted(4, 1), label: "Distribution readout", x: chart_gutter, y: 2, width: chart_plot, value: readout_text, color: Theme.ink, align: Start })
		axis = [
			rule({ key: painted(5, 1), label: "Distribution axis", x1: chart_gutter, y1: bottom, x2: chart_gutter + chart_plot, y2: bottom, stroke: Theme.edge }),
			caption({ key: painted(5, 2), label: "Distribution count", x: 0, y: top - 2, width: chart_gutter - 6, value: tallest.to_str(), color: Theme.dim, align: End }),
		]
		# Hit rectangles last, so they are the topmost targets.
		hits = shown.map(|found| box({ key: (found.bucket + 1).to_u64_wrap(), label: "Bucket ${range_text(found.bucket)}", x: chart_gutter + (found.bucket - first) * width, y: top, width, height: bottom - top, fill: Default }))
		count_of : I64 -> I64
		count_of = |bucket| match counts.get(bucket.to_u64_wrap()) {
			Ok(found) => found.count
			Err(_) => 0
		}
		scope_caption = match scope {
			All => "every trigger"
			Only(chosen_trigger) => "${chosen_trigger.trigger} · ${chosen_trigger.patch_kind}"
		}
		[
			heading("DURATION DISTRIBUTION · ${state.phase} · ${scope_caption} · octave buckets · warmups excluded"),
			Gui.canvas({
				label: "Duration distribution",
				primitives: hover_mark.concat(bars).concat(edges).concat(axis).concat(markers).append(readout).concat(hits),
				on_pointer: |current, event| match (event.phase, target_of(event.target, Capture.bucket_count)) {
					(Begin, Some(bucket)) => Observatory.ask(current, FilterBucket(bucket, count_of(bucket)))
					_ => Gui.none
				},
				on_hover: Some(
					|current, event| {
						hovered = match event.phase {
							Move => target_of(event.target, Capture.bucket_count)
							Leave => None
						}
						if hovered == current.bucket_hover Gui.none else Gui.update({ ..current, bucket_hover: hovered })
					},
				),
				width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
				height: Px(166),
				min_width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
				min_height: Px(166),
				bg: Theme.card,
				border_color: Theme.line,
				border_width: 1,
				radius: Theme.radius,
			}),
		]
	}
}

## Frames (W5, US-22 to US-25)

strip_top : I64
strip_top = 22

strip_bottom : I64
strip_bottom = 172

## One stage of a bar, stacked on the stages below it.
stage : { layer : I64, column : I64, below : I64, part : I64, scale : I64, color : Gui.Color, name : Str } -> Gui.CanvasPrimitive
stage = |props| {
	base = pixels(props.below, props.scale, strip_bottom - strip_top)
	top = pixels(props.below + props.part, props.scale, strip_bottom - strip_top)
	box({ key: painted(props.layer, props.column), label: "${props.name} ${props.column.to_str()}", x: chart_gutter + props.column * 3, y: strip_bottom - top, width: 2, height: top - base, fill: props.color })
}

frame_name : I64, I64 -> Str
frame_name = |run_id, ordinal| "r${run_id.to_str()} #${ordinal.to_str()}"

bar_total : Capture.Bar -> I64
bar_total = |bar| bar.layout + bar.prepaint + bar.paint

## Layout solve and presentation happen inside GPUI, outside any host-owned
## element. They are drawn as bands that say so, never as zero.
unavailable_band : Capture.Opened, I64, Str, Str -> List(Gui.CanvasPrimitive)
unavailable_band = |opened, row, name, family_name| {
	y = strip_bottom + 8 + row * 18
	reason = match Capture.family(opened, family_name) {
		Found(found) => "${found.status}: ${found.reason}"
		Missing => "not recorded in this capture"
	}
	[
		box({ key: painted(7, row), label: "Unavailable ${name}", x: chart_gutter, y, width: chart_plot, height: 14, fill: Theme.rail }),
		caption({ key: painted(8, row), label: "Reason ${name}", x: chart_gutter + 6, y: y + 1, width: chart_plot - 12, value: "${name} ${reason}", color: Theme.dim, align: Start }),
	]
}

## Zooming halves or doubles the span of frames around the pointer's frame,
## and a sideways scroll pans by an eighth of it.
zoomed : Capture.Strip, Gui.EventCanvasWheel -> [None, Some({ start : I64, span : I64 })]
zoomed = |strip, wheel| {
	smallest = if strip.total < Capture.columns strip.total else Capture.columns
	offset = if wheel.x.to_i64() < chart_gutter 0 else if wheel.x.to_i64() > chart_gutter + chart_plot chart_plot else wheel.x.to_i64() - chart_gutter
	anchor = strip.start + offset * strip.span / chart_plot
	requested = if wheel.dy < 0 strip.span / 2 else if wheel.dy > 0 strip.span * 2 else strip.span
	span = if requested < smallest smallest else if requested > strip.total strip.total else requested
	panned = if wheel.dx > 0 span / 8 else if wheel.dx < 0 -(span / 8) else 0
	unclamped = anchor - offset * span / chart_plot + panned
	start = if unclamped < 0 0 else if unclamped > strip.total - span strip.total - span else unclamped
	if start == strip.start and span == strip.span None else Some({ start, span })
}

frame_strip : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
frame_strip = |state, opened| {
	strip = state.strip.strip
	budget = Capture.budget_ns(state.budget)
	slowest = strip.bars.fold(0, |most, bar| if bar_total(bar) > most bar_total(bar) else most)
	scale = if budget * 3 / 2 > slowest budget * 3 / 2 else slowest
	budget_y = strip_bottom - pixels(budget, scale, strip_bottom - strip_top)
	columns = strip.bars.len().to_i64_wrap()
	bars = strip.bars.fold(
		[],
		|drawn, bar| {
			over = if bar_total(bar) > budget [box({ key: painted(4, bar.column), label: "Over budget ${bar.column.to_str()}", x: chart_gutter + bar.column * 3, y: strip_top - 6, width: 2, height: 3, fill: Theme.alarm_ink })] else []
			drawn
				.concat(
					[
						stage({ layer: 1, column: bar.column, below: 0, part: bar.layout, scale, color: Theme.callback, name: "Layout request" }),
						stage({ layer: 2, column: bar.column, below: bar.layout, part: bar.prepaint, scale, color: Theme.span, name: "Prepaint" }),
						stage({ layer: 3, column: bar.column, below: bar.layout + bar.prepaint, part: bar.paint, scale, color: Theme.validate, name: "Paint" }),
					],
				)
				.concat(over)
		},
	)
	hovered = match state.frame_hover {
		Some(column) => match strip.bars.get(column.to_u64_wrap()) {
			Ok(bar) => Some(bar)
			Err(_) => None
		}
		None => None
	}
	readout_text = match hovered {
		Some(bar) => {
			verdict = if bar_total(bar) > budget "✗ over budget" else "✓ within budget"
			many = if bar.frames > 1 " · costliest of ${bar.frames.to_str()} frames" else ""
			"frame ${frame_name(bar.run_id, bar.ordinal)} · layout request ${Format.ms(bar.layout)} · prepaint ${Format.ms(bar.prepaint)} · paint ${Format.ms(bar.paint)} = ${Format.ms(bar_total(bar))} ${verdict}${many}"
		}
		None => "Hover a frame for its stages; press it to inspect; scroll to zoom."
	}
	highlight = match state.frame_hover {
		Some(column) => [box({ key: painted(9, 1), label: "Hovered column", x: chart_gutter + column * 3 - 1, y: strip_top, width: 4, height: strip_bottom - strip_top, fill: Theme.selected })]
		None => []
	}
	selected = match state.frame {
		Some(detail) => match strip.bars.find_first(|bar| bar.id == detail.id) {
			Ok(bar) => [rule({ key: painted(9, 2), label: "Selected frame", x1: chart_gutter + bar.column * 3 + 1, y1: strip_top - 10, x2: chart_gutter + bar.column * 3 + 1, y2: strip_bottom, stroke: Theme.accent })]
			Err(_) => []
		}
		None => []
	}
	guides = [
		rule({ key: painted(5, 1), label: "Frame axis", x1: chart_gutter, y1: strip_bottom, x2: chart_gutter + chart_plot, y2: strip_bottom, stroke: Theme.edge }),
		rule({ key: painted(5, 2), label: "Budget line", x1: chart_gutter, y1: budget_y, x2: chart_gutter + chart_plot, y2: budget_y, stroke: Theme.alarm_ink }),
		caption({ key: painted(5, 3), label: "Budget caption", x: 0, y: budget_y - 7, width: chart_gutter - 6, value: Format.ms(budget), color: Theme.alarm_ink, align: End }),
		caption({ key: painted(5, 4), label: "Scale caption", x: 0, y: strip_top - 6, width: chart_gutter - 6, value: Format.ms(scale), color: Theme.dim, align: End }),
		caption({ key: painted(5, 5), label: "Frame readout", x: chart_gutter, y: 2, width: chart_plot, value: readout_text, color: Theme.ink, align: Start }),
	]
	bands = unavailable_band(opened, 0, "layout solve", "gpui_layout_solve").concat(unavailable_band(opened, 1, "presentation", "gpui_presentation"))
	hits = strip.bars.map(|bar| box({ key: (bar.column + 1).to_u64_wrap(), label: "Frame ${frame_name(bar.run_id, bar.ordinal)}", x: chart_gutter + bar.column * 3, y: strip_top, width: 3, height: strip_bottom - strip_top, fill: Default }))
	bar_at : I64 -> [None, Some(Capture.Bar)]
	bar_at = |column| match strip.bars.get(column.to_u64_wrap()) {
		Ok(bar) => Some(bar)
		Err(_) => None
	}
	last = strip.start + strip.span
	span_caption = if strip.span == strip.total "all ${strip.total.to_str()} frames" else "frames ${(strip.start + 1).to_str()}–${last.to_str()} of ${strip.total.to_str()}"
	whole = if strip.span < strip.total [key({ caption: "Whole capture", label: "Show every frame", selected: False, on_press: |current, _| Observatory.ask(current, ShowFrames(0, 0)) })] else []
	[
		Gui.row(
			{ label: "Strip heading", width: Fill, padding: 0, gap: Theme.inset, align: Center },
			[meta("FRAMES · stacked: layout request · prepaint · paint · ${span_caption} · ${columns.to_str()} columns")].concat(whole),
		),
		Gui.canvas({
			label: "Frames",
			primitives: highlight.concat(bars).concat(guides).concat(selected).concat(bands).concat(hits),
			on_pointer: |current, event| match (event.phase, target_of(event.target, columns)) {
				(Begin, Some(column)) => match bar_at(column) {
					Some(bar) => Observatory.ask(current, SelectFrame(bar))
					None => Gui.none
				}
				_ => Gui.none
			},
			on_hover: Some(
				|current, event| {
					column = match event.phase {
						Move => target_of(event.target, columns)
						Leave => None
					}
					if column == current.frame_hover Gui.none else Gui.update({ ..current, frame_hover: column })
				},
			),
			on_wheel: Some(
				|current, wheel| match zoomed(current.strip.strip, wheel) {
					Some(next) => Observatory.ask(current, ShowFrames(next.start, next.span))
					None => Gui.none
				},
			),
			width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
			height: Px(214),
			min_width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
			min_height: Px(214),
			bg: Theme.card,
			border_color: Theme.line,
			border_width: 1,
			radius: Theme.radius,
		}),
	]
}

budget_bar : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
budget_bar = |state, opened| {
	over = match opened.budgets.find_first(|found| found.hz == state.budget) {
		Ok(found) => found.over
		Err(_) => 0
	}
	Gui.row(
		{ label: "Budget", width: Fill, padding: 0, gap: 6, align: Center },
		[meta("BUDGET")]
			.concat(Capture.budget_rates.map(|hz| key({ caption: "${hz.to_str()} Hz", label: "Budget ${hz.to_str()} Hz", selected: state.budget == hz, on_press: |current, _| Gui.delegate({ ..current, budget: hz }) })))
			.append(Gui.row({ label: "Frame summary", padding: 0, gap: 0, grow: True, justify: End, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("${opened.frames.drawn.to_str()} frames · ${over.to_str()} over budget")])),
	)
}

## The frame a press opened: its stages against the budget, and its own work.
frame_detail : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
frame_detail = |state, opened| match state.frame {
	None => [note("Press a frame in the strip to inspect it.")]
	Some(detail) => {
		total = detail.layout + detail.prepaint + detail.paint
		budget = Capture.budget_ns(state.budget)
		# The name takes what the figure leaves, so the figures keep the right
		# edge however wide the inspector is.
		figure = |name, value| labelled_row("Frame ${name}", [rest_cell(name, Theme.dim), figure_cell(value, 150)])
		count = |metric| match detail.work.find_first(|found| found.metric == metric) {
			Ok(found) => found.count.to_str()
			Err(_) => "—"
		}
		share = match Capture.replay_share(detail.work) {
			Some(percent) => "${percent.to_str()}%"
			None => "no scene operations"
		}
		[
			Gui.row({ label: "Frame title", padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("FRAME ${frame_name(detail.run_id, detail.ordinal)}")]),
			figure("layout request", Format.ms(detail.layout)),
			figure("prepaint", Format.ms(detail.prepaint)),
			figure("paint", Format.ms(detail.paint)),
			Gui.row(
				{ label: "Frame verdict", width: Fill, padding: 0, gap: 0, fg: if total > budget Theme.alarm_ink else Theme.good, font_size: Theme.body, font_face: Theme.face },
				[Gui.text(if total > budget "= ${Format.ms(total)} ✗ over ${Format.ms(budget)}" else "= ${Format.ms(total)} ✓ within ${Format.ms(budget)}")],
			),
		]
			.concat(TimelineView.causes(opened, detail))
			.concat([
			heading("FRAME WORK"),
			figure("replay share", share),
			figure("fresh scene ops", count(14)),
			figure("replayed scene ops", count(6)),
			figure("cached paint", count(5)),
		])
	}
}

tenths_text : I64, I64 -> Str
tenths_text = |total, frames| if frames <= 0 {
	"—"
} else {
	scaled_total = total * 10 / frames
	"${(scaled_total / 10).to_str()}.${(scaled_total % 10).to_str()}"
}

## US-23: every node kind, both metrics, over every frame and in the frame a
## press opened. A kind with no row in a recorded frame did no such work.
native_work : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
native_work = |state, opened| {
	drawn = opened.frames.drawn
	present = Capture.complete(opened, "gpui_native_work")
	totals = |metric, kind| match opened.native.find_first(|found| found.metric == metric and found.kind == kind) {
		Ok(found) => { total: found.total, max: found.max }
		Err(_) => { total: 0, max: 0 }
	}
	chosen = |metric, kind| match state.frame {
		Some(detail) => match detail.native.find_first(|found| found.metric == metric and found.kind == kind) {
			Ok(found) => found.count.to_str()
			Err(_) => "0"
		}
		None => ""
	}
	cells = |metric, kind| {
		found = totals(metric, kind)
		[
			family_cell(opened, "gpui_native_work", found.total.to_str(), 70),
			family_cell(opened, "gpui_native_work", found.max.to_str(), 60),
			family_cell(opened, "gpui_native_work", tenths_text(found.total, drawn), 60),
			figure_cell(chosen(metric, kind), 70),
		]
	}
	rows = Capture.node_kinds.map_with_index(
		|name, index| {
			kind = index.to_i64_wrap()
			labelled_row("Native ${name}", [cell(name, 130, Theme.ink)].concat(cells(0, kind)).concat(cells(1, kind)).append(rest_cell("", Theme.dim)))
		},
	)
	selected = match state.frame {
		Some(detail) => "frame ${frame_name(detail.run_id, detail.ordinal)}"
		None => "no frame"
	}
	reason = if present [] else [absence_note(opened, "gpui_native_work")]
	[heading("NATIVE WORK · renders and elements created · total · max · mean per frame · ${selected}")]
		.concat(reason)
		.concat(
			[
				table(
					"Native work",
					[
						table_head(
							"Native work columns",
							[head_cell("kind", 130), head_figure("renders", 70), head_figure("max", 60), head_figure("mean", 60), head_figure("frame", 70), head_figure("created", 70), head_figure("max", 60), head_figure("mean", 60), head_figure("frame", 70), head_rest("")],
						),
					].concat(rows),
				),
			],
		)
}

group_name : [Replayed, Fresh, Moved] -> Str
group_name = |group| match group {
	Replayed => "cached and replayed"
	Fresh => "fresh"
	Moved => "moved and rebased"
}

## US-24: the nineteen GPUI frame-work metrics, grouped.
frame_work : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
frame_work = |state, opened| {
	drawn = opened.frames.drawn
	present = Capture.complete(opened, "gpui_frame_work")
	total_of = |metric| match opened.work.find_first(|found| found.metric == metric) {
		Ok(found) => found
		Err(_) => { metric, total: 0, max: 0 }
	}
	chosen = |metric| match state.frame {
		Some(detail) => match detail.work.find_first(|found| found.metric == metric) {
			Ok(found) => found.count.to_str()
			Err(_) => "—"
		}
		None => ""
	}
	metric_row = |metric, name| {
		found = total_of(metric)
		labelled_row(
			"Frame work ${name}",
			[
				cell(name, 250, Theme.ink),
				family_cell(opened, "gpui_frame_work", found.total.to_str(), 90),
				family_cell(opened, "gpui_frame_work", found.max.to_str(), 70),
				family_cell(opened, "gpui_frame_work", tenths_text(found.total, drawn), 70),
				figure_cell(chosen(metric), 70),
				rest_cell("", Theme.dim),
			],
		)
	}
	group_rows = |group| {
		members = Capture.work_metrics.map_with_index(|found, index| { index: index.to_i64_wrap(), name: found.name, group: found.group }).keep_if(|found| found.group == group)
		[table_row([rest_cell(group_name(group), Theme.dim)])].concat(members.map(|found| metric_row(found.index, found.name)))
	}
	replayed = total_of(6).total
	fresh = total_of(14).total
	overall = if !present "replay share —" else if replayed + fresh == 0 "replay share: no scene operations" else "replay share over every frame: ${Format.percent(replayed, replayed + fresh)} of scene operations replayed"
	frame_share = match state.frame {
		Some(detail) => match Capture.replay_share(detail.work) {
			Some(percent) => " · frame ${frame_name(detail.run_id, detail.ordinal)}: ${percent.to_str()}%"
			None => " · frame ${frame_name(detail.run_id, detail.ordinal)}: no scene operations"
		}
		None => ""
	}
	reason = if present [] else [absence_note(opened, "gpui_frame_work")]
	[heading("FRAME WORK · GPUI replay against fresh construction")]
		.concat(reason)
		.concat(
			[
				Gui.row({ label: "Replay share", width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text("${overall}${frame_share}")]),
				table(
					"Frame work",
					[table_head("Frame work columns", [head_cell("metric", 250), head_figure("total", 90), head_figure("max", 70), head_figure("mean", 70), head_figure("frame", 70), head_rest("")])]
						.concat(group_rows(Replayed))
						.concat(group_rows(Fresh))
						.concat(group_rows(Moved)),
				),
			],
		)
}

## A list the platform builds the viewport and one viewport either side of
## materialises at most three times what it shows; beyond that it is flagged.
list_flag : Capture.ListRow -> { text : Str, ink : Gui.Color }
list_flag = |found| if found.visible > 0 and found.materialized > 3 * found.visible {
	{ text: "⚠ ${(found.materialized / found.visible).to_str()}× visible", ink: Theme.caution }
} else {
	{ text: "✓", ink: Theme.good }
}

## US-25: every virtual list's last pass, and its passes over time.
virtual_lists : Observatory.State, Capture.Opened -> List(Gui.Elem(Observatory.State))
virtual_lists = |_state, opened| {
	present = Capture.complete(opened, "virtual_list_materialization")
	rows = opened.lists.map(
		|found| {
			marked = list_flag(found)
			labelled_row(
				"List ${found.list_id.to_str()}",
				[
					cell("#${found.list_id.to_str()}", 90, Theme.ink),
					figure_cell(found.passes.to_str(), 70),
					figure_cell(found.visible.to_str(), 70),
					figure_cell(found.materialized.to_str(), 100),
					figure_cell(found.recycled.to_str(), 80),
					figure_cell(found.live.to_str(), 70),
					figure_cell(found.most.to_str(), 90),
					rest_cell(marked.text, marked.ink),
				],
			)
		},
	)
	tallest = opened.passes.fold(0, |most, found| if found.materialized > most found.materialized else most)
	top = 8
	bottom = 88
	pass_bars = opened.passes.map(
		|found| {
			height = pixels(found.materialized, tallest, bottom - top)
			box({ key: painted(1, found.column), label: "Pass ${found.column.to_str()}", x: chart_gutter + found.column * 3, y: bottom - height, width: 2, height, fill: Theme.span })
		},
	)
	visible_marks = opened.passes.map(
		|found| {
			y = bottom - pixels(found.visible, tallest, bottom - top)
			box({ key: painted(2, found.column), label: "Pass visible ${found.column.to_str()}", x: chart_gutter + found.column * 3, y, width: 3, height: 1, fill: Theme.ink })
		},
	)
	chart_captions = [
		caption({ key: painted(3, 1), label: "Pass scale", x: 0, y: top - 4, width: chart_gutter - 6, value: tallest.to_str(), color: Theme.dim, align: End }),
		caption({ key: painted(3, 2), label: "Pass legend", x: chart_gutter, y: bottom + 4, width: chart_plot, value: "materialised entities per pass, oldest first; the dark tick is the rows visible", color: Theme.dim, align: Start }),
	]
	body = if !present {
		[absence_note(opened, "virtual_list_materialization")]
	} else {
		[
			table(
				"Virtual lists",
				[table_head("Virtual list columns", [head_cell("list", 90), head_figure("passes", 70), head_figure("visible", 70), head_figure("materialised", 100), head_figure("recycled", 80), head_figure("live", 70), head_figure("most", 90), head_rest("")])].concat(rows),
			),
			Gui.canvas({
				label: "List passes",
				primitives: pass_bars.concat(visible_marks).concat(chart_captions),
				on_pointer: |_, _| Gui.none,
				width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
				height: Px(110),
				min_width: Px((chart_gutter + chart_plot + 8).to_u32_wrap()),
				min_height: Px(110),
				bg: Theme.card,
				border_color: Theme.line,
				border_width: 1,
				radius: Theme.radius,
			}),
		]
	}
	[heading("VIRTUAL LISTS · last pass · most materialised in any pass")].concat(body)
}

same_frame : Observatory.State, Observatory.State -> Bool
same_frame = |a, b| frame_id(a) == frame_id(b)

frame_id : Observatory.State -> [None, Some(I64)]
frame_id = |state| match state.frame {
	Some(detail) => Some(detail.id)
	None => None
}

## A capture whose frame spans were not recorded, such as a semantic-headless
## one, shows the family's status and reason instead of any chart.
frames_view : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
frames_view = |_state, opened| if !Capture.complete(opened, "gpui_frame_spans") {
	reason = match Capture.family(opened, "gpui_frame_spans") {
		Found(found) => "Frames ${found.status}: ${found.reason}"
		Missing => "Frames not recorded: this capture has no gpui_frame_spans family"
	}
	Gui.col(
		{ label: "Frames", width: Fill, padding: Theme.inset, gap: Theme.inset },
		[
			heading("FRAMES"),
			Gui.panel(
				{ label: "Frames absent", width: Fill, padding: Theme.inset, gap: 4, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				[
					Gui.row({ label: "Frames status", width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face }, [Gui.text(reason)]),
					absence_note(opened, "gpui_frame_spans"),
					note("Record a capture of a GPUI window, such as a window specification run with --host-stats-output, to see its frames."),
				],
			),
		],
	)
} else {
	Gui.col(
		{ label: "Frames", width: Fill, padding: Theme.inset, gap: Theme.inset },
		[
			part_boundary("Frame budget", |a, b| same_capture(a, b) and a.budget == b.budget, section(|current, captured| [budget_bar(current, captured)])),
			part_boundary(
				"Frame strip",
				|a, b| same_capture(a, b) and a.budget == b.budget and a.strip.read == b.strip.read and a.frame_hover == b.frame_hover and same_frame(a, b),
				section(frame_strip),
			),
			part_boundary("Native work", |a, b| same_capture(a, b) and same_frame(a, b), section(native_work)),
			part_boundary("Frame work", |a, b| same_capture(a, b) and same_frame(a, b), section(frame_work)),
			part_boundary("Virtual lists", same_capture, section(virtual_lists)),
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
		|a, b| same_capture(a, b) and a.phase == b.phase and a.trigger_sort == b.trigger_sort and a.filter == b.filter and a.inspected == b.inspected and same_cycles(a, b) and CompareView.same_comparison(a, b),
		|current| with_capture(current, |s, o| scrolled("Interactions scroll", interactions(s, o))),
	)
	## The strip's hover is compared only by the strip, which a hover updates
	## in place.
	Frames => view_boundary("Frames", |a, b| same_capture(a, b) and a.budget == b.budget and a.strip.read == b.strip.read and same_frame(a, b), |current| with_capture(current, |s, o| scrolled("Frames scroll", frames_view(s, o))))
	Timeline => view_boundary("Timeline", TimelineView.same_view, |current| with_capture(current, |s, o| scrolled("Timeline scroll", TimelineView.timeline(s, o))))
	Spec => view_boundary("Spec", |a, b| same_capture(a, b) and a.run == b.run and a.step_focus == b.step_focus and a.steps.window.read == b.steps.window.read and a.step_scroll == b.step_scroll and SourceView.same(a, b), |current| with_capture(current, spec))
	Memory => view_boundary("Memory", |a, b| same_capture(a, b) and a.phase == b.phase and CompareView.same_comparison(a, b), |current| with_capture(current, |s, o| scrolled("Memory scroll", memory(s, o))))
	Health => view_boundary("Health", |a, b| same_capture(a, b) and a.family_focus == b.family_focus, |current| with_capture(current, |s, o| scrolled("Health scroll", health(s, o))))
	Compare => view_boundary("Compare", CompareView.same_view, |current| scrolled("Compare scroll", CompareView.compare(current)))
	Scaling => view_boundary("Scaling", ScalingView.same_view, |current| scrolled("Scaling scroll", ScalingView.scaling(current)))
}

workspace : Observatory.State -> Gui.Elem(Observatory.State)
workspace = |state| Gui.col(
	{ label: "Capture", width: Fill, height: Fill, grow: True, min_height: Px(0), overflow_y: Clip, padding: 0, gap: 0 },
	[
		view_boundary("Capture bar", |a, b| same_capture(a, b) and a.changed == b.changed and Observatory.watching(a) == Observatory.watching(b), |current| with_capture(current, capture_bar)),
		view_boundary("Trust banner", same_capture, |current| with_capture(current, |_, opened| banner(opened))),
		view_boundary("Baseline bar", CompareView.same_comparison, CompareView.baseline_bar),
		Gui.row(
			{ label: "Workspace", width: Fill, height: Fill, grow: True, min_height: Px(0), overflow_y: Clip, padding: 0, gap: 0, bg: Theme.paper },
			[
				view_boundary("Views", |a, b| a.view == b.view, nav),
				Gui.split(
					{
						label: "Inspector divider",
						side: End,
						size: state.inspector.size,
						min: 240,
						max: 1100,
						collapsible: True,
						collapsed: state.inspector.collapsed,
						on_resize: |current, event| Gui.update({ ..current, inspector: { ..current.inspector, size: event.size, collapsed: event.collapsed } }),
						thickness: 5,
						color: Theme.line,
						hover_color: Theme.edge,
						active_color: Theme.accent,
						focus_color: Theme.accent,
					},
					main_view(state),
					view_boundary("Inspector pane", same_inspector, inspector_pane),
				),
			],
		),
	],
)

## The shell's inspector (§6): the detail of whatever the view on screen, or
## the view it is pinned to, has selected, so every view drills down in the
## same place. It renders only when that selection changes.
same_inspector : Observatory.State, Observatory.State -> Bool
same_inspector = |a, b| {
	shown = Observatory.inspected_view(a)
	pinned = |state| match state.inspector.pinned {
		Some(_) => True
		None => False
	}
	shown == Observatory.inspected_view(b)
	and pinned(a) == pinned(b)
	and same_capture(a, b)
	and (
		match shown {
			# An inspected cycle lays its waterfall out for the inspector's width.
			Interactions => a.inspected == b.inspected and a.inspector_focus == b.inspector_focus and CompareView.same_comparison(a, b) and (a.inspected == None or a.inspector.size == b.inspector.size)
			Frames => a.budget == b.budget and same_frame(a, b)
			Timeline => TimelineView.same_view(a, b)
			Spec => a.run == b.run and a.step_focus == b.step_focus and a.steps.window.read == b.steps.window.read and SourceView.same(a, b)
			_ => True
		}
	)
}

inspector_pane : Observatory.State -> Gui.Elem(Observatory.State)
inspector_pane = |state| {
	shown = Observatory.inspected_view(state)
	pinned = match state.inspector.pinned {
		Some(_) => True
		None => False
	}
	bar = Gui.row(
		{ label: "Inspector bar", width: Fill, padding: 0, gap: 6, align: Center },
		[
			meta("INSPECTOR · ${Observatory.view_name(shown)}"),
			Gui.row(
				{ padding: 0, gap: 6, grow: True, justify: End },
				[
					key({ caption: if pinned "Unpin" else "Pin", label: if pinned "Unpin inspector" else "Pin inspector", selected: pinned, on_press: |current, _| Gui.update(toggle_pin(current)) }),
					# The split that folds the inspector is the window's, so the
					# change is the root's to render.
					key({ caption: "Hide", label: "Hide inspector", selected: False, on_press: |current, _| Gui.delegate({ ..current, inspector: { ..current.inspector, collapsed: True } }) }),
				],
			),
		],
	)
	Gui.col(
		{ label: "Inspector", width: Fill, height: Fill, grow: True, min_height: Px(0), padding: Theme.inset, gap: Theme.inset, bg: Theme.rail },
		[
			bar,
			# Notes wrap to the inspector's width; a detail wider than it, such as
			# a waterfall's bars, shows in full once the divider widens it.
			Gui.scroll({ label: "Inspector scroll", width: Fill, height: Fill, grow: True, content: Gui.col({ width: Fill, padding: 0, gap: Theme.inset }, inspector_body(state, shown)) }),
		],
	)
}

## Pinning keeps the inspector on the view on screen; unpinning lets it
## follow the view again.
toggle_pin : Observatory.State -> Observatory.State
toggle_pin = |current| {
	pinned = match current.inspector.pinned {
		Some(_) => None
		None => Some(current.view)
	}
	{ ..current, inspector: { ..current.inspector, pinned } }
}

inspector_body : Observatory.State, Observatory.View -> List(Gui.Elem(Observatory.State))
inspector_body = |state, shown| match state.capture {
	None => []
	Some(opened) => match shown {
		Interactions => [inspector_part(state)]
		Frames => [
			Gui.col(
				{ label: "Frame inspector", width: Fill, padding: Theme.inset, gap: 4, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				frame_detail(state, opened),
			),
		]
		Timeline => [TimelineView.detail]
		Spec => if Observatory.annotated(state) [SourceView.step_inspector(state, opened)] else focused_step(state)
		other => [note("${Observatory.view_name(other)} has nothing to inspect. Pin the inspector on a view to keep its selection beside every other.")]
	}
}

## The capture bar's tabs (§6): one per open capture, the baseline's marked
## ◆. Switching keeps each capture's view as it was left; `+` keeps the one on
## screen open and lists the folder to choose another.
capture_tabs : Observatory.State -> Gui.Elem(Observatory.State)
capture_tabs = |state| {
	selected = match Observatory.on_screen_tab(state) {
		Some(on_screen) => on_screen.to_str()
		None => ""
	}
	items = state.tabs.map(|tab| { key: tab.key.to_str(), title: if Observatory.holds_baseline(state, tab) "◆ ${tab.name}" else tab.name, closable: True })
	more = match state.capture {
		Some(_) => [key({ caption: "+", label: "Open another capture", selected: False, on_press: |current, _| Observatory.ask(current, ShowCaptures) })]
		None => []
	}
	Gui.row(
		{ label: "Capture tabs row", width: Fill, padding: 0, padding_left: Px(Theme.inset), padding_right: Px(Theme.inset), padding_top: Px(4), gap: 6, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		[
			Gui.tabs({
				label: "Capture tabs",
				width: Auto,
				tabs: items,
				selected,
				on_select: |current, event| Observatory.ask(current, SwitchTab(tab_key(event.key))),
				on_close: |current, event| Observatory.ask(current, CloseTab(tab_key(event.key))),
				font_size: Theme.body,
				font_face: Theme.face,
				fg: Theme.dim,
				selected_fg: Theme.ink,
				selected_bg: Theme.paper,
				hover_bg: Theme.quiet_hover,
				accent: Theme.accent,
				border_color: Theme.line,
				focus_color: Theme.accent,
			}),
		]
			.concat(more),
	)
}

tab_key : Str -> U64
tab_key = |text| U64.from_str(text) ?? 0

same_tabs : Observatory.State, Observatory.State -> Bool
same_tabs = |a, b| {
	titles = |state| state.tabs.map(|tab| { key: tab.key, baseline: Observatory.holds_baseline(state, tab) })
	titles(a) == titles(b) and Observatory.on_screen_tab(a) == Observatory.on_screen_tab(b) and (a.capture == None) == (b.capture == None)
}

render : Observatory.State -> Gui.Elem(Observatory.State)
render = |state| {
	palette = match state.palette {
		Open(_) => [view_boundary("Palette", PaletteView.same_view, PaletteView.palette)]
		Closed => []
	}
	Gui.col(
		{ label: "Observatory", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.paper, fg: Theme.ink, font_size: Theme.body },
		[
			header(state),
			authority_bar(state),
			error_band(state),
		]
			.concat(if state.tabs.is_empty() [] else [view_boundary("Capture tabs", same_tabs, capture_tabs)])
			.concat([
			match state.capture {
				Some(_) => workspace(state)
				None => view_boundary("Capture list", |a, b| folder_revision(a.folder) == folder_revision(b.folder) and a.capture_sort == b.capture_sort, capture_list)
			},
		])
			.concat(palette),
	)
		.shortcuts(window_keys)
}
