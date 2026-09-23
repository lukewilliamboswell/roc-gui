## Observatory's state, the one folder it may read, and the asynchronous
## transitions between them. Every read of a capture runs as a worker task and
## carries a request identity, so a superseded open cannot replace a newer one.
## The mounted presentation lives in `View.roc`.
import pf.Gui
import Capture

## What the application holds over the filesystem. Nothing chosen yet, a
## dismissed chooser, and a host refusal call for different next steps.
Grant : [Ungranted, Declined, Granted(Str), Refused]

## `revision` is the request that listed the folder, so a view can tell two
## listings apart without comparing the directory handle.
Folder : { revision : U64, name : Str, directory : Gui.FilesDirRead, captures : List(Capture.Listing) }

Status : [Busy(U64), Failed({ message : Str, remedy : Str }), Ready]

View : [Overview, Interactions, Spec, Memory, Health]

## A table's order: the column index and its direction.
Sort : { column : U64, descending : Bool }

## The cycle list shows every trigger of the phase, or one trigger and patch
## kind chosen from the triggers table.
Filter : [All, Only({ trigger : Str, patch_kind : Str })]

## What a view inside a component boundary asks of the application as a whole:
## work that needs a handle only the root holds, or a change a sibling view
## must show. A boundary forwards it by delegation, and the root fulfils it.
Request : [Open(Str), Inspect(Capture.Cycle), ShowStep(I64, I64), SelectRun(I64), Show(View), ShowFamily(Str), CloseCapture]

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
	capture_sort : Sort,
	trigger_sort : Sort,
	filter : Filter,
	inspected : [None, Some(Capture.Inspected)],
	## The ordinal of the step "Show step" opened, in the selected run.
	step_focus : [None, Some(I64)],
	family_focus : [None, Some(Str)],
	## Set only between a handler and the root that fulfils it; a rendered
	## state never carries one.
	request : [None, Some(Request)],
}

Observatory := [].{
	Folder : Folder
	Grant : Grant
	State : State
	Status : Status
	View : View
	Sort : Sort
	Filter : Filter
	Request : Request

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
		capture_sort: { column: 0, descending: False },
		trigger_sort: { column: 4, descending: True },
		filter: All,
		inspected: None,
		step_focus: None,
		family_focus: None,
		request: None,
	}

	## Ask the root for something a boundary cannot do itself.
	ask : State, Request -> Gui.Action(State)
	ask = |state, request| Gui.delegate({ ..state, request: Some(request) })

	## A nested boundary's delegation policy: a request continues to the root,
	## and any other change is accepted here, so it renders this boundary's
	## parent and not the whole window.
	forward : State -> Gui.Action(State)
	forward = |state| match state.request {
		Some(_) => Gui.delegate(state)
		None => Gui.update(state)
	}

	## The policy of a boundary directly under the root: perform the request,
	## or accept the change as a root update.
	fulfil : State -> Gui.Action(State)
	fulfil = fulfil

	## Pressing a column's heading orders by it; pressing it again reverses.
	resort : Sort, U64 -> Sort
	resort = |sort, column| if sort.column == column { column, descending: !sort.descending } else { column, descending: False }

	sort_captures : State, U64 -> State
	sort_captures = |state, column| { ..state, capture_sort: resort(state.capture_sort, column) }

	sort_triggers : State, U64 -> State
	sort_triggers = |state, column| { ..state, trigger_sort: resort(state.trigger_sort, column) }

	## Pressing the selected trigger again shows every trigger.
	filter_trigger : State, Str, Str -> State
	filter_trigger = |state, trigger, patch_kind| {
		chosen = Only({ trigger, patch_kind })
		{ ..state, filter: if state.filter == chosen All else chosen }
	}

	close_inspector : State -> State
	close_inspector = |state| { ..state, inspected: None }

	choose : State -> Gui.Action(State)
	choose = choose

	choose_file : State -> Gui.Action(State)
	choose_file = choose_file

	set_phase : State, Str -> State
	set_phase = |state, phase| { ..state, phase, filter: All }
}

fulfil : State -> Gui.Action(State)
fulfil = |asked| {
	state = { ..asked, request: None }
	match asked.request {
		None => Gui.update(state)
		Some(Open(name)) => match state.folder {
			Some(folder) => open_capture(state, folder.directory, name)
			None => Gui.update(state)
		}
		Some(Inspect(cycle)) => inspect(state, cycle)
		## Open the Spec view at the step, by ordinal, that drove a cycle.
		Some(ShowStep(run_id, ordinal)) => select_run({ ..state, view: Spec, step_focus: Some(ordinal) }, run_id)
		Some(SelectRun(run_id)) => select_run(state, run_id)
		Some(Show(view)) => Gui.update({ ..state, view, step_focus: None, family_focus: None })
		## Open Health at the family a `—` belongs to.
		Some(ShowFamily(name)) => Gui.update({ ..state, view: Health, family_focus: Some(name) })
		Some(CloseCapture) => Gui.update(close_capture(state))
	}
}

## A read still in flight keeps its request, so its result is still accepted
## or superseded as it would be with the capture open.
close_capture : State -> State
close_capture = |state| {
	status = match state.status {
		Busy(active) => Busy(active)
		_ => Ready
	}
	{ ..state, capture: None, inspected: None, status }
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
				Ok(entries) => {
					# The listing is bound before the record is built. Written inline
					# beside `directory: selection.directory`, an optimized build loses
					# a reference to the capability: see "A value used twice in one
					# record literal" in wip/issues-backlog.md.
					captures = list_captures!(selection.directory, entries)
					ChosenFolder({ revision: id, name: selection.name, directory: selection.directory, captures })
				}
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

## The file chooser offers captures only, and the host refuses any other file.
capture_types : List(Gui.FilesFileType)
capture_types = [{ label: "roc-gui captures", extensions: ["rgstats"], mime_types: [] }]

unreadable_remedy : Str
unreadable_remedy = "Nothing from this file is shown. Observatory reads only schema 19 captures written by the roc-gui recorder."

## Open one capture the person chooses, without a folder. The folder grant, if
## any, is kept: a single file is a separate grant beside it.
choose_file : State -> Gui.Action(State)
choose_file = |state| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match state.access.pick_file!(capture_types) {
			Ok(Chosen(selection)) => OpenedFile(Capture.open_file!(selection.file, selection.name))
			Ok(Canceled) => FileCanceled
			Err(PickFileErr(Unsupported)) => FileRefused("Only .rgstats files are captures.")
			Err(_) => FileRefused("The host granted no file to read. Start Observatory with --host-cap-file <capture>, or choose a .rgstats file this process may read.")
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				OpenedFile(Ok(opened)) => Gui.update(show(latest, opened, id))
				OpenedFile(Err(message)) => Gui.update({ ..latest, capture: None, status: failure(message, unreadable_remedy) })
				FileCanceled => Gui.update({ ..latest, status: Ready })
				FileRefused(remedy) => Gui.update({ ..latest, status: failure("Could not open the capture file", remedy) })
			}
			_ => Gui.none
		},
	})
}

## An opened capture replaces the one on screen, at its overview.
show : State, Capture.Opened, U64 -> State
show = |latest, opened, id| { ..latest, capture: Some({ ..opened, revision: id }), view: Overview, phase: default_phase(opened), run: first_run(opened), filter: All, inspected: None, step_focus: None, family_focus: None, status: Ready }

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
				Ok(opened) => Gui.update(show(latest, opened, id))
				Err(message) => Gui.update({ ..latest, capture: None, status: failure(message, unreadable_remedy) })
			}
			_ => Gui.none
		},
	})
}

## A cycle's detail is read through the connection the open capture holds.
inspect : State, Capture.Cycle -> Gui.Action(State)
inspect = |state, cycle| match state.capture {
	None => Gui.none
	Some(opened) => {
		id = state.next_request
		Gui.task({
			pending: { ..state, next_request: id + 1, status: Busy(id) },
			run: || Capture.inspect!(opened.database, cycle),
			resolve: |latest, outcome| match latest.status {
				Busy(active) if active == id => match outcome {
					Ok(inspected) => Gui.update({ ..latest, inspected: Some(inspected), status: Ready })
					Err(message) => Gui.update({ ..latest, status: failure(message, "This cycle's detail could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
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
						Ok(page) => Gui.update({ ..latest, capture: Some({ ..current, revision: id, steps: page.steps, steps_more: page.more }), run: run_id, status: Ready })
						Err(message) => Gui.update({ ..latest, status: failure(message, "The steps of this run could not be read from the open capture.") })
					}
				}
				_ => Gui.none
			},
		})
	}
}
