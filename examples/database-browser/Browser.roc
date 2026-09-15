import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Sqlite
import Query

Browser := [].{
	State : State
	init : State
	init = { database: None, folder: None, next_request: 0, query: "SELECT id, title, price FROM books ORDER BY id LIMIT 100", result: None, schema: [], status: Ready }
	render : State -> Elem(State)
	render = render
}

Folder : { directory : Files.Dir.Read, entries : List(Files.Entry) }

Status : [Busy(U64), Failed(Str), Ready]

State : { database : [None, Some(Sqlite.Read)], folder : [None, Some(Folder)], next_request : U64, query : Str, result : [None, Some(Sqlite.Result)], schema : List(Str), status : Status }

choose = |state| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Files.pick_directory!() {
			Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
				Ok(entries) => ChosenFolder({ directory: selection.directory, entries })
				Err(_) => ChooseFailed
			}
			Ok(Canceled) => ChooseCanceled
			Err(_) => ChooseFailed
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				ChosenFolder(folder) => Action.update({ ..latest, folder: Some(folder), status: Ready })
				ChooseCanceled => Action.update({ ..latest, status: Ready })
				ChooseFailed => Action.update({ ..latest, status: Failed("Could not open the database folder") })
			}
			_ => Action.none
		},
	})
}

open_database = |state, directory, name| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Sqlite.open_read!(directory, name) {
			Err(error) => Err(OpenFailed("Could not open SQLite database: ${Sqlite.detail(error)}"))
			Ok(database) => match Sqlite.query!(database, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
				Err(error) => Err(OpenFailed("Could not inspect SQLite schema: ${Sqlite.detail(error)}"))
				Ok(result) => Ok({ database, result })
			}
		},
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Err(OpenFailed(message)) => Action.update({ ..latest, status: Failed(message) })
				Ok(opened) => Action.update({
					..latest,
					database: Some(opened.database),
					schema: opened.result.rows.map(
						|row| match row.first() {
							Ok(value) => Query.value_text(value)
							Err(_) => ""
						},
					),
					result: None,
					status: Ready,
				})
			}
			_ => Action.none
		},
	})
}

run_query = |state, database, sql| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || Sqlite.query!(database, sql),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(result) => Action.update({ ..latest, result: Some(result), status: Ready })
				Err(error) => Action.update({ ..latest, status: Failed(Sqlite.detail(error)) })
			}
			_ => Action.none
		},
	})
}

render : State -> Elem(State)
render = |state| {
	database_files = match state.folder {
		None => []
		Some(folder) => folder.entries.keep_if(|entry| entry.kind == File).map(|entry| Elem.button({ label: entry.name, name: "Open database ${entry.name}", on_press: |current, _| open_database(current, folder.directory, entry.name) }))
	}
	schema = state.schema.map(|name| Elem.text("Table: ${name}"))
	rows = match state.result {
		None => []
		Some(result) => result.rows.map_with_index(|row, index| Elem.VirtualListItem.{ key: index, content: Elem.text("Result row ${index.to_str()}: ${Query.row_text(row)}") })
	}
	result_view = match state.result {
		None => Elem.text("Run a query to inspect rows")
		Some(result) => Elem.col(
			Elem.ColProps.{ width: Fill, height: Fill, grow: True },
			[
				Elem.text("Columns: ${Str.join_with(result.columns, ", ")}"),
				Elem.text("Rows: ${result.rows.len().to_str()}"),
				Elem.virtual_list(Elem.VirtualListProps.{ name: "Query rows", row_height: 28, items: rows }),
			],
		)
	}
	query_area = match state.database {
		None => []
		Some(database) => [
			Elem.textarea(Elem.TextareaProps.{ label: "SQL query", value: state.query, on_input: |current, event| Action.update({ ..current, query: event.value }), height: Px(90) }),
			Elem.button({ label: "Run query", name: "Run query", on_press: |current, _| run_query(current, database, current.query) }),
		]
	}
	status = match state.status {
		Ready => []
		Busy(_) => [Elem.text("Working…")]
		Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Database error", width: Fill }, [Elem.text(message)])]
	}
	Elem.col(Elem.ColProps.{ label: "Database browser", width: Fill, height: Fill, grow: True, padding: 20 }, [Elem.text("SQLite Database Browser"), Elem.button({ label: "Choose database folder", name: "Choose database folder", on_press: |current, _| choose(current) })].concat(status).concat([Elem.row(Elem.RowProps.{ width: Fill }, [Elem.col(Elem.ColProps.{ label: "Database files", width: Px(220) }, database_files), Elem.col(Elem.ColProps.{ label: "Database schema", width: Px(220) }, schema)])]).concat(query_area).concat([result_view]))
}
