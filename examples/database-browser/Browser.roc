## The browser's state, the authority it currently holds over one folder, and
## the asynchronous transitions between them. The mounted presentation lives in
## `View.roc`.
import pf.Program
import pf.Action
import pf.Files
import pf.Sqlite
import Query

## What the browser holds over the filesystem.
##
## The grant is a real consent flow: a person chooses a folder at the host's
## picker and the browser is handed read authority over that folder and nothing
## else. The three unhappy answers are genuinely different and are kept apart,
## because "you have not chosen yet", "you chose not to" and "the host refused"
## call for three different next steps.
Grant : [Ungranted, Declined, Granted(Str), Refused]

Folder : { name : Str, directory : Files.Dir.Read, entries : List(Files.Entry) }

Status : [Busy(U64), Failed({ message : Str, remedy : Str }), Ready]

State : {
	access : Program.Access,
	database : [None, Some(Sqlite.Db)],
	folder : [None, Some(Folder)],
	grant : Grant,
	next_request : U64,
	open_name : Str,
	query : Str,
	result : [None, Some(Sqlite.Result)],
	schema : List(Str),
	status : Status,
}

Browser := [].{
	Folder : Folder
	Grant : Grant
	State : State
	Status : Status
	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Program.Access -> State
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
	choose : State -> Action(State)
	choose = choose
	open_database : State, Files.Dir.Read, Str -> Action(State)
	open_database = open_database
	run_query : State, Sqlite.Db, Str -> Action(State)
	run_query = run_query
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
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Files.pick_directory!(state.access) {
			Ok(Chosen(selection)) => match selection.directory.list!() {
				Ok(entries) => ChosenFolder({ name: selection.name, directory: selection.directory, entries })
				Err(_) => ChooseFailed
			}
			Ok(Canceled) => ChooseCanceled
			Err(_) => ChooseFailed
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				ChosenFolder(folder) => Action.update({ ..latest, folder: Some(folder), grant: Granted(folder.name), status: Ready })
				ChooseCanceled => Action.update({ ..latest, grant: still_held_or_declined(latest.grant), status: Ready })
				ChooseFailed => Action.update({
					..latest,
					grant: Refused,
					status: failure(
						"Could not open the database folder",
						"The host granted no folder to read. Start the browser with --host-cap-dir <folder>, or choose one this process may read.",
					),
				})
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
			Ok(database) => match database.query!("SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
				Err(error) => Err(OpenFailed("Could not inspect SQLite schema: ${Sqlite.detail(error)}"))
				Ok(result) => Ok({ database, result })
			}
		},
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Err(OpenFailed(message)) => Action.update({
					..latest,
					status: failure(message, "The grant covers this folder, but this file is not a database this browser can read."),
				})
				Ok(opened) => Action.update({
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
			_ => Action.none
		},
	})
}

run_query = |state, database, sql| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || database.query!(sql),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(result) => Action.update({ ..latest, result: Some(result), status: Ready })
				Err(error) => Action.update({
					..latest,
					status: failure(
						Sqlite.detail(error),
						"The browser holds a read-only handle on this file. Read statements only; nothing here can change the database.",
					),
				})
			}
			_ => Action.none
		},
	})
}
