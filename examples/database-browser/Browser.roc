## The browser's state, the authority it currently holds over one folder, and
## the asynchronous transitions between them. The mounted presentation lives in
## `View.roc`.
import pf.Gui
import Query

## What the browser holds over the filesystem.
##
## The grant is a real consent flow: a person chooses a folder at the host's
## picker and the browser is handed read authority over that folder and nothing
## else. The three unhappy answers are genuinely different and are kept apart,
## because "you have not chosen yet", "you chose not to" and "the host refused"
## call for three different next steps.
Grant : [Ungranted, Declined, Granted(Str), Refused]

Folder : { name : Str, directory : Gui.FilesDirRead, entries : List(Gui.FilesEntry) }

Status : [Busy(U64), Failed({ message : Str, remedy : Str }), Ready]

## One page of a query's result, and where it sits in the whole: the statement
## that produced it (not the editor's current text, which may since have
## changed), the zero-based row the page starts at, and the page itself.
Shown : { sql : Str, offset : U64, page : Gui.SqlitePage }

State : {
	access : Gui.Access,
	database : [None, Some(Gui.SqliteDb)],
	folder : [None, Some(Folder)],
	grant : Grant,
	next_request : U64,
	open_name : Str,
	query : Str,
	result : [None, Some(Shown)],
	schema : List(Str),
	status : Status,
}

Browser := [].{
	Folder : Folder
	Grant : Grant
	Shown : Shown
	State : State
	Status : Status

	## Rows in one page of a result: the host's page limit.
	page_rows : U64
	page_rows = 10_000

	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Gui.Access -> State
	init = |access| {
		access,
		database: None,
		folder: None,
		grant: Ungranted,
		next_request: 0,
		open_name: "",
		query: "SELECT id, title, price FROM books ORDER BY id LIMIT 100",
		result: None,
		schema: [],
		status: Ready,
	}
	choose : State -> Gui.Action(State)
	choose = choose
	open_database : State, Gui.FilesDirRead, Str -> Gui.Action(State)
	open_database = open_database
	run_query : State, Gui.SqliteDb, Str -> Gui.Action(State)
	run_query = |state, database, sql| run_page(state, database, sql, 0)
	## Fetch the page of the shown result that starts at `offset`.
	turn_page : State, Gui.SqliteDb, Shown, U64 -> Gui.Action(State)
	turn_page = |state, database, shown, offset| run_page(state, database, shown.sql, offset)
	set_query : State, Str -> State
	set_query = |state, query| { ..state, query }
}

failure = |message, remedy| Failed({ message, remedy })

## Dismissing the picker withdraws nothing. A folder already granted stays
## granted; only a browser that never held one records the refusal to choose.
still_held_or_declined = |grant| match grant {
	Granted(name) => Granted(name)
	_ => Declined
}

## Choosing a folder is the browser's one consent flow, so its three unhappy
## endings stay apart: nothing chosen yet, a picker the person dismissed, and a
## host that refused to open one at all.
choose = |state| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match state.access.pick_directory!() {
			Ok(Chosen(selection)) => match selection.directory.list!() {
				Ok(entries) => ChosenFolder({ name: selection.name, directory: selection.directory, entries })
				Err(_) => ChooseFailed
			}
			Ok(Canceled) => ChooseCanceled
			Err(_) => ChooseFailed
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				ChosenFolder(folder) => Gui.update({ ..latest, folder: Some(folder), grant: Granted(folder.name), status: Ready })
				ChooseCanceled => Gui.update({ ..latest, grant: still_held_or_declined(latest.grant), status: Ready })
				ChooseFailed => Gui.update({
					..latest,
					grant: Refused,
					status: failure(
						"Could not open the database folder",
						"The host granted no folder to read. Start the browser with --host-cap-dir <folder>, or choose one this process may read.",
					),
				})
			}
			_ => Gui.none
		},
	})
}

open_database = |state, directory, name| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Gui.Sqlite.open_read!(directory, name) {
			Err(error) => Err(OpenFailed("Could not open SQLite database: ${Gui.Sqlite.detail(error)}"))
			Ok(database) => match database.query!("SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
				Err(error) => Err(OpenFailed("Could not inspect SQLite schema: ${Gui.Sqlite.detail(error)}"))
				Ok(result) => Ok({ database, result })
			}
		},
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Err(OpenFailed(message)) => Gui.update({
					..latest,
					status: failure(message, "The grant covers this folder, but this file is not a database this browser can read."),
				})
				Ok(opened) => Gui.update({
					..latest,
					database: Some(opened.database),
					open_name: name,
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
			_ => Gui.none
		},
	})
}

## The first page is the statement exactly as written, so any read-only
## statement runs. A later page wraps it and binds the offset as a parameter;
## the host cuts the page and reports whether rows follow it.
page_request : Str, U64 -> { sql : Str, params : List(Gui.SqliteValue), rows : U64 }
page_request = |sql, offset| if offset == 0 {
	{ sql, params: [], rows: Browser.page_rows }
} else {
	body = sql.trim().drop_suffix(";")
	{ sql: "SELECT * FROM (${body}) LIMIT -1 OFFSET ?", params: [Integer(offset.to_i64_wrap())], rows: Browser.page_rows }
}

run_page : State, Gui.SqliteDb, Str, U64 -> Gui.Action(State)
run_page = |state, database, sql, offset| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || database.page!(page_request(sql, offset)),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(page) => Gui.update({ ..latest, result: Some({ sql, offset, page }), status: Ready })
				Err(error) => Gui.update({
					..latest,
					status: failure(
						Gui.Sqlite.detail(error),
						"The browser holds a read-only handle on this file. Read statements only; nothing here can change the database.",
					),
				})
			}
			_ => Gui.none
		},
	})
}
