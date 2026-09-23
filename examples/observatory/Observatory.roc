## Observatory's state, the one folder it may read, and the asynchronous
## transitions between them. Every read of a capture runs as a worker task and
## carries a request identity, so a superseded open cannot replace a newer one.
## The mounted presentation lives in `View.roc`.
import pf.Gui
import Capture

## What the application holds over the filesystem. Nothing chosen yet, a
## dismissed chooser, and a host refusal call for different next steps.
Grant : [Ungranted, Declined, Granted(Str), Refused]

Folder : { name : Str, directory : Gui.FilesDirRead, captures : List(Capture.Listing) }

Status : [Busy(U64), Failed({ message : Str, remedy : Str }), Ready]

View : [Overview, Interactions, Spec, Health]

State : {
	access : Gui.Access,
	folder : [None, Some(Folder)],
	grant : Grant,
	next_request : U64,
	capture : [None, Some(Capture.Opened)],
	view : View,
	phase : Str,
	run : I64,
	status : Status,
}

Observatory := [].{
	Folder : Folder
	Grant : Grant
	State : State
	Status : Status
	View : View

	init : Gui.Access -> State
	init = |access| {
		access,
		folder: None,
		grant: Ungranted,
		next_request: 0,
		capture: None,
		view: Overview,
		phase: "measured",
		run: 0,
		status: Ready,
	}

	choose : State -> Gui.Action(State)
	choose = choose

	open_capture : State, Gui.FilesDirRead, Str -> Gui.Action(State)
	open_capture = open_capture

	close_capture : State -> State
	close_capture = |state| {
		status = match state.status {
			Busy(active) => Busy(active)
			_ => Ready
		}
		{ ..state, capture: None, status }
	}

	show : State, View -> State
	show = |state, view| { ..state, view }

	set_phase : State, Str -> State
	set_phase = |state, phase| { ..state, phase }

	select_run : State, I64 -> Gui.Action(State)
	select_run = select_run
}

failure = |message, remedy| Failed({ message, remedy })

still_held_or_declined = |grant| match grant {
	Granted(name) => Granted(name)
	_ => Declined
}

## Only `.rgstats` files are captures. Everything else in a benchmark output
## folder is left out of the list rather than reported as a failure.
is_capture : Gui.FilesEntry -> Bool
is_capture = |entry| entry.kind == File and Str.ends_with(entry.name, ".rgstats")

list_captures! : Gui.FilesDirRead, List(Gui.FilesEntry) => List(Capture.Listing)
list_captures! = |directory, entries| {
	var $listed = []
	for entry in entries.keep_if(is_capture) {
		$listed = $listed.append(Capture.summarize!(directory, entry.name))
	}
	$listed
}

choose : State -> Gui.Action(State)
choose = |state| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match state.access.pick_directory!() {
			Ok(Chosen(selection)) => match selection.directory.list!() {
				Ok(entries) => ChosenFolder({ name: selection.name, directory: selection.directory, captures: list_captures!(selection.directory, entries) })
				Err(_) => ChooseFailed
			}
			Ok(Canceled) => ChooseCanceled
			Err(_) => ChooseFailed
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				ChosenFolder(folder) => Gui.update({ ..latest, folder: Some(folder), grant: Granted(folder.name), capture: None, status: Ready })
				ChooseCanceled => Gui.update({ ..latest, grant: still_held_or_declined(latest.grant), status: Ready })
				ChooseFailed => Gui.update({
					..latest,
					grant: Refused,
					status: failure(
						"Could not open the capture folder",
						"The host granted no folder to read. Start Observatory with --host-cap-dir <folder>, or choose one this process may read.",
					),
				})
			}
			_ => Gui.none
		},
	})
}

## An interactive session has no measured phase, so its cycles are shown by
## default instead.
default_phase : Capture.Opened -> Str
default_phase = |opened| if opened.runs.any(|run| run.phase == "interactive") "interactive" else "measured"

first_run : Capture.Opened -> I64
first_run = |opened| match opened.runs.first() {
	Ok(run) => run.id
	Err(_) => 0
}

open_capture : State, Gui.FilesDirRead, Str -> Gui.Action(State)
open_capture = |state, directory, name| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || Capture.open!(directory, name),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(opened) => Gui.update({ ..latest, capture: Some(opened), view: Overview, phase: default_phase(opened), run: first_run(opened), status: Ready })
				Err(message) => Gui.update({
					..latest,
					capture: None,
					status: failure(message, "Nothing from this file is shown. Observatory reads only schema 19 captures written by the roc-gui recorder."),
				})
			}
			_ => Gui.none
		},
	})
}

## Steps are read one run at a time from the connection the open capture holds.
select_run : State, I64 -> Gui.Action(State)
select_run = |state, run_id| match state.capture {
	None => Gui.none
	Some(opened) => {
		id = state.next_request
		Gui.task({
			pending: { ..state, next_request: id + 1, status: Busy(id) },
			run: || Capture.run_steps!(opened.database, run_id),
			resolve: |latest, outcome| match latest.status {
				Busy(active) if active == id => match latest.capture {
					None => Gui.update({ ..latest, status: Ready })
					Some(current) => match outcome {
						Ok(page) => Gui.update({ ..latest, capture: Some({ ..current, steps: page.steps, steps_more: page.more }), run: run_id, status: Ready })
						Err(message) => Gui.update({ ..latest, status: failure(message, "The steps of this run could not be read from the open capture.") })
					}
				}
				_ => Gui.none
			},
		})
	}
}
