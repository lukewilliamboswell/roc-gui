## The mounted ledger: a header, a standing readout of the folder authority, the
## granted folder's files, the opened database's tables, and the query bench.
import pf.Action
import pf.Elem
import Browser
import Query
import Theme
import "icons/folder.svg" as folder_icon : List(U8)
import "icons/folder-check.svg" as folder_check_icon : List(U8)
import "icons/folder-x.svg" as folder_x_icon : List(U8)

View := [].{
	render : Browser.State -> Elem(Browser.State)
	render = render
}

meta = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Elem.text(caption)],
)

divider = Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.edge, font_size: Theme.meta },
	[Elem.text("|")],
)

trailing_meta = |caption| Elem.row(
	Elem.RowProps.{ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Elem.text(caption)],
)

## A note in place of content: an empty column, an unopened database. Set in the
## same quiet type as a label, because it is a statement of fact and not an
## alarm about one.
note = |caption| Elem.row(
	Elem.RowProps.{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta },
	[Elem.text(caption)],
)

quiet_key = |props| Elem.action_button(
	Elem.ActionButtonProps.{
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
	},
)

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
	Elem.row(
		Elem.RowProps.{
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
			Elem.image(Elem.ImageProps.{ label: reading.name, bytes: reading.icon, format: Svg, width: Px(14), height: Px(14) }),
			meta("FOLDER"),
			Elem.row(
				Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.meta, font_face: Theme.face, max_width: Px(320), text_overflow: Ellipsis },
				[Elem.text(reading.held)],
			),
			divider,
			Elem.row(
				Elem.RowProps.{ label: "Folder verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta },
				[Elem.text(reading.verdict)],
			),
			quiet_key({ caption: "Choose folder…", label: "Choose database folder", on_press: |current, _| Browser.choose(current), width: Auto }),
		],
	)
}

error_band = |state| match state.status {
	Failed(problem) => Elem.panel(
		Elem.PanelProps.{
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
			Elem.row(Elem.RowProps.{ padding: 0, gap: 0, font_size: Theme.body }, [Elem.text(problem.message)]),
			Elem.row(Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Elem.text(problem.remedy)]),
		],
	)
	_ => Elem.row(Elem.RowProps.{ padding: 0, gap: 0, height: Px(0) }, [])
}

files_column = |state| {
	body = match state.folder {
		None => [note("Nothing is readable until a folder is granted.")]
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
	Elem.col(
		Elem.ColProps.{
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
			|name| Elem.row(
				Elem.RowProps.{ width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
				[Elem.text("Table: ${name}")],
			),
		)
	}
	Elem.col(
		Elem.ColProps.{
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
cell = |text, ink, size| Elem.row(
	Elem.RowProps.{
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
	},
	[Elem.text(text)],
)

gutter = |text| Elem.row(
	Elem.RowProps.{ width: Px(Theme.gutter), padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
	[Elem.text(text)],
)

result_table = |result| {
	header = Elem.row(
		Elem.RowProps.{
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
		[gutter("ROW")].concat(result.columns.map(|name| cell(name, Theme.dim, Theme.meta))),
	)
	rows = result.rows.map_with_index(
		|row, index| Elem.VirtualListItem.{
			key: index,
			content: Elem.row(
				Elem.RowProps.{
					width: Fill,
					height: Px(Theme.row_height),
					padding: 0,
					padding_left: Px(Theme.inset),
					gap: 0,
					border_color: Theme.line,
					border_width: 0,
					border_bottom: Px(1),
				},
				[gutter("Result row ${index.to_str()}")].concat(row.map(|value| cell(Query.value_text(value), Theme.ink, Theme.body))),
			),
		},
	)
	Elem.col(
		Elem.ColProps.{ label: "Result table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
		[header, Elem.virtual_list(Elem.VirtualListProps.{ name: "Query rows", row_height: Theme.row_height, items: rows })],
	)
}

query_bench = |state| {
	editor = match state.database {
		None => [note("Open a database from the folder to write a query against it.")]
		Some(database) => [
			Elem.textarea(
				Elem.TextareaProps.{
					label: "SQL query",
					value: state.query,
					placeholder: "SELECT * FROM books LIMIT 100",
					on_input: |current, event| Action.update(Browser.set_query(current, event.value)),
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
				},
			),
			Elem.row(
				Elem.RowProps.{ label: "Query controls", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[
					Elem.action_button(
						Elem.ActionButtonProps.{
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
						},
					),
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
			Elem.row(Elem.RowProps.{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.body }, [Elem.text("Run a query to inspect rows")]),
		]
		Some(value) => [
			Elem.row(
				Elem.RowProps.{ label: "Result summary", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[meta("Columns: ${Str.join_with(value.columns, ", ")}"), trailing_meta("Rows: ${value.rows.len().to_str()}")],
			),
			result_table(value),
		]
	}
	Elem.col(
		Elem.ColProps.{ label: "Query bench", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset, bg: Theme.paper },
		[meta("SQL")].concat(editor).concat(result),
	)
}

header = |state| Elem.row(
	Elem.RowProps.{
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
		Elem.text("DATABASE BROWSER"),
		divider,
		meta("sqlite, read only"),
		divider,
		trailing_meta(if Str.is_empty(state.open_name) "no database open" else state.open_name),
	],
)

render : Browser.State -> Elem(Browser.State)
render = |state| Elem.col(
	Elem.ColProps.{
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
		Elem.row(
			Elem.RowProps.{ label: "Ledger", width: Fill, height: Fill, grow: True, padding: 0, gap: 0 },
			[files_column(state), schema_column(state), query_bench(state)],
		),
	],
)
