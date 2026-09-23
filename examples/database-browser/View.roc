## The mounted ledger: a header, a standing readout of the folder authority, the
## granted folder's files, the opened database's tables, and the query bench.
import pf.Gui
import Browser
import Query
import Theme
import "icons/folder.svg" as folder_icon : List(U8)
import "icons/folder-check.svg" as folder_check_icon : List(U8)
import "icons/folder-x.svg" as folder_x_icon : List(U8)

View := [].{
	render : Browser.State -> Gui.Elem(Browser.State)
	render = render
}

meta = |caption| Gui.row(
	{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

divider = Gui.row(
	{ padding: 0, gap: 0, fg: Theme.edge, font_size: Theme.meta },
	[Gui.text("|")],
)

trailing_meta = |caption| Gui.row(
	{ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

## A note in place of content: an empty column, an unopened database. Set in the
## same quiet type as a label, because it is a statement of fact and not an
## alarm about one.
note = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta },
	[Gui.text(caption)],
)

quiet_key = |props| Gui.button({
	caption: props.caption,
	label: props.label,
	on_press: props.on_press,
	width: props.width,
	padding: 6,
	font_size: Theme.body,
	font_face: Theme.face,
	radius: Theme.radius,
	bg: Theme.quiet,
	hover_bg: Theme.quiet_hover,
	active_bg: Theme.quiet_active,
	fg: Theme.ink,
	border_color: Theme.line,
	border_width: 1,
	text_overflow: Ellipsis,
})

## The browser holds read authority over exactly one folder, handed to it by a
## person at the host's picker. The bar says which folder that is, or which of
## the three ways it has none: never asked, asked and dismissed, or refused.
authority_bar = |state| {
	reading = match state.grant {
		Ungranted => { icon: folder_icon, name: "No folder granted", held: "no folder granted", verdict: "choose a folder to read", ink: Theme.dim }
		Declined => { icon: folder_icon, name: "Folder choice dismissed", held: "no folder granted", verdict: "you closed the picker without choosing", ink: Theme.dim }
		Granted(folder) => { icon: folder_check_icon, name: "Folder granted", held: folder, verdict: "read-only, this folder only", ink: Theme.ink }
		Refused => { icon: folder_x_icon, name: "Folder grant refused", held: "no folder granted", verdict: "the host refused a folder", ink: Theme.alarm_ink }
	}
	Gui.row(
		{
			label: "Authority bar",
			width: Fill,
			padding: Theme.inset,
			gap: Theme.inset,
			align: Center,
			bg: Theme.rail,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
			font_size: Theme.meta,
		},
		[
			Gui.image({ label: reading.name, bytes: reading.icon, format: Svg, width: Px(14), height: Px(14) }),
			meta("FOLDER"),
			Gui.row(
				{ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.meta, font_face: Theme.face, max_width: Px(320), text_overflow: Ellipsis },
				[Gui.text(reading.held)],
			),
			divider,
			Gui.row(
				{ label: "Folder verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta },
				[Gui.text(reading.verdict)],
			),
			quiet_key({ caption: "Choose folder…", label: "Choose database folder", on_press: |current, _| Browser.choose(current), width: Auto }),
		],
	)
}

error_band = |state| match state.status {
	Failed(problem) => Gui.panel(
		{
			label: "Database error",
			width: Fill,
			padding: Theme.inset,
			gap: 2,
			bg: Theme.alarm,
			fg: Theme.alarm_ink,
			border_color: Theme.alarm_line,
			border_width: 0,
			border_bottom: Px(1),
			radius: 0,
		},
		[
			Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text(problem.message)]),
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(problem.remedy)]),
		],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

files_column = |state| {
	body = match state.folder {
		None => [note("No folder granted yet.")]
		Some(folder) => {
			files = folder.entries.keep_if(|entry| entry.kind == File)
			if files.is_empty() {
				[note("The granted folder holds no files.")]
			} else {
				files.map(
					|entry| quiet_key({
						caption: entry.name,
						label: "Open database ${entry.name}",
						on_press: |current, _| Browser.open_database(current, folder.directory, entry.name),
						width: Fill,
					}),
				)
			}
		}
	}
	Gui.col(
		{
			label: "Database files",
			width: Px(Theme.files_width),
			height: Fill,
			padding: Theme.inset,
			gap: 6,
			bg: Theme.rail,
			border_color: Theme.line,
			border_width: 0,
			border_right: Px(1),
		},
		[meta("FILES IN FOLDER")].concat(body),
	)
}

schema_column = |state| {
	body = if state.schema.is_empty() {
		[note("Open a file to read its tables.")]
	} else {
		state.schema.map(
			|name| Gui.row(
				{ width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
				[Gui.text("Table: ${name}")],
			),
		)
	}
	Gui.col(
		{
			label: "Database schema",
			width: Px(Theme.schema_width),
			height: Fill,
			padding: Theme.inset,
			gap: 6,
			bg: Theme.rail,
			border_color: Theme.line,
			border_width: 0,
			border_right: Px(1),
		},
		[meta(if Str.is_empty(state.open_name) "TABLES" else "TABLES IN ${state.open_name}")].concat(body),
	)
}

## One cell of the result table. Every column takes an equal share of the width
## and clips rather than wraps, so a row is always one line tall and the columns
## stay on the same vertical rules from the header down.
cell = |text, ink, size, justify| Gui.row(
	{
		width: Fill,
		grow: True,
		padding: 0,
		padding_right: Px(Theme.inset),
		gap: 0,
		fg: ink,
		font_size: size,
		font_face: Theme.face,
		text_overflow: Ellipsis,
		align: Center,
		justify,
	},
	[Gui.text(text)],
)

## A ledger aligns its numbers on the right so the decimal points stack and a
## column reads down. Text stays on the left. A column's alignment is taken from
## the first row's value types and applied to the heading too, so the heading
## sits over its own column rather than beside it.
justify_for = |value| match value {
	Integer(_) => End
	Real(_) => End
	_ => Start
}

alignments = |result| match result.rows.first() {
	Ok(row) => row.map(justify_for)
	Err(_) => result.columns.map(|_| Start)
}

gutter = |text| Gui.row(
	{ width: Px(Theme.gutter), padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
	[Gui.text(text)],
)

result_table = |result, offset, scroll_request| {
	columns_justify = alignments(result)
	header = Gui.row(
		{
			label: "Result columns",
			width: Fill,
			height: Px(Theme.row_height),
			padding: 0,
			padding_left: Px(Theme.inset),
			gap: 0,
			bg: Theme.rail,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
		},
		[gutter("ROW")].concat(result.columns.map_with_index(|name, index| cell(name, Theme.dim, Theme.meta, columns_justify.get(index) ?? Start))),
	)
	# Only the rows near the viewport are ever built, so a page of ten thousand
	# rows costs what a screenful does.
	render_row : U64 -> Gui.Elem(Browser.State)
	render_row = |index| Gui.row(
		{
			width: Fill,
			height: Px(Theme.row_height),
			padding: 0,
			padding_left: Px(Theme.inset),
			gap: 0,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
		},
		[gutter("Result row ${(offset + index).to_str()}")].concat((result.rows.get(index) ?? []).map_with_index(|value, column| cell(Query.value_text(value), Theme.ink, Theme.body, columns_justify.get(column) ?? Start))),
	)
	Gui.col(
		{ label: "Result table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
		[
			header,
			Gui.virtual_rows({
				label: "Query rows",
				row_height: Theme.row_height,
				count: result.rows.len(),
				render_row,
				scroll_to: scroll_request,
				on_range: Some(|current, rows| Gui.update(Browser.show_rows(current, rows))),
			}),
		],
	)
}

## Keys that move the result to its first or last row, and the rows the
## viewport shows, numbered as the gutter numbers them.
row_keys : Browser.State, Browser.Shown -> List(Gui.Elem(Browser.State))
row_keys = |state, shown| {
	count = shown.page.rows.len()
	if count == 0 {
		[]
	} else {
		on_screen = match state.on_screen {
			Some(rows) if rows.end > rows.start => [meta("On screen ${(shown.offset + rows.start + 1).to_str()}–${(shown.offset + rows.end).to_str()}")]
			_ => []
		}
		on_screen.concat(
			[
				quiet_key({ caption: "First row", label: "Scroll to first row", on_press: |current, _| Gui.update(Browser.scroll_rows(current, 0, Start)), width: Auto }),
				quiet_key({ caption: "Last row", label: "Scroll to last row", on_press: |current, _| Gui.update(Browser.scroll_rows(current, count - 1, End)), width: Auto }),
			],
		)
	}
}

## A result longer than one page names the rows on screen and turns to the
## neighbouring pages. A result that fits in one page shows no pager at all.
pager : Browser.State, Browser.Shown -> List(Gui.Elem(Browser.State))
pager = |state, shown| match state.database {
	Some(database) if shown.offset > 0 or shown.page.more => {
		first = shown.offset + 1
		last = shown.offset + shown.page.rows.len()
		turn = |caption, offset| quiet_key({ caption, label: caption, on_press: |current, _| Browser.turn_page(current, database, shown, offset), width: Auto })
		earlier = if shown.offset > 0 [turn("Previous page", if shown.offset > Browser.page_rows shown.offset - Browser.page_rows else 0)] else []
		later = if shown.page.more [turn("Next page", last)] else []
		[
			Gui.row(
				{ label: "Result pages", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				earlier.concat(later).concat([trailing_meta("Rows ${first.to_str()}–${last.to_str()}${if shown.page.more ", more follow" else ", end of result"}")]),
			),
		]
	}
	_ => []
}

query_bench = |state| {
	editor = match state.database {
		None => [note("Open a database from the folder to write a query against it.")]
		Some(database) => [
			Gui.textarea({
				label: "SQL query",
				value: state.query,
				placeholder: "SELECT * FROM books LIMIT 100",
				on_input: |current, event| Gui.update(Browser.set_query(current, event.value)),
				width: Fill,
				height: Px(76),
				padding: Theme.inset,
				font_size: Theme.body,
				font_face: Theme.face,
				bg: Theme.card,
				fg: Theme.ink,
				border_color: Theme.edge,
				border_width: 1,
				radius: Theme.radius,
			}),
			Gui.row(
				{ label: "Query controls", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[
					Gui.button({
						caption: "Run query",
						label: "Run query",
						on_press: |current, _| Browser.run_query(current, database, current.query),
						padding: 6,
						font_size: Theme.body,
						radius: Theme.radius,
						bg: Theme.accent,
						hover_bg: Theme.accent_hover,
						active_bg: Theme.accent_active,
						fg: Theme.on_accent,
					}),
					trailing_meta(
						match state.status {
							Busy(_) => "running…"
							_ => "read-only handle on ${state.open_name}"
						},
					),
				],
			),
		]
	}
	result = match state.result {
		None => [
			Gui.row({ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.body }, [Gui.text("Run a query to inspect rows")]),
		]
		Some(shown) => [
			Gui.row(
				{ label: "Result summary", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[meta("Columns: ${Str.join_with(shown.page.columns, ", ")}"), trailing_meta("Rows: ${shown.page.rows.len().to_str()}")].concat(row_keys(state, shown)),
			),
		]
			.concat(pager(state, shown))
			.concat([result_table(shown.page, shown.offset, state.rows_scroll)])
	}
	Gui.col(
		{ label: "Query bench", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset, bg: Theme.paper },
		[meta("SQL")].concat(editor).concat(result),
	)
}

header = |state| Gui.row(
	{
		label: "Browser header",
		width: Fill,
		padding: Theme.inset,
		gap: 8,
		align: Center,
		bg: Theme.rail,
		border_color: Theme.line,
		border_width: 0,
		border_bottom: Px(1),
		fg: Theme.ink,
		font_size: Theme.meta,
	},
	[
		Gui.text("DATABASE BROWSER"),
		divider,
		meta("sqlite, read only"),
		divider,
		trailing_meta(if Str.is_empty(state.open_name) "no database open" else state.open_name),
	],
)

render : Browser.State -> Gui.Elem(Browser.State)
render = |state| Gui.col(
	{
		label: "Database browser",
		width: Fill,
		height: Fill,
		grow: True,
		padding: 0,
		gap: Theme.seam,
		bg: Theme.paper,
		fg: Theme.ink,
		font_size: Theme.body,
	},
	[
		header(state),
		authority_bar(state),
		error_band(state),
		Gui.row(
			{ label: "Ledger", width: Fill, height: Fill, grow: True, padding: 0, gap: 0 },
			[files_column(state), schema_column(state), query_bench(state)],
		),
	],
)
