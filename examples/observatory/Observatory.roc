## Observatory's state, the one folder it may read, and the asynchronous
## transitions between them. Every read of a capture runs as a worker task and
## carries a request identity, so a superseded open cannot replace a newer one.
## The mounted presentation lives in `View.roc`.
import pf.Gui
import Capture
import History
import Scaling
import Timeline

## What the application holds over the filesystem. Nothing chosen yet, a
## dismissed chooser, and a host refusal call for different next steps.
Grant : [Ungranted, Declined, Granted(Str), Refused]

## `revision` is the request that listed the folder, so a view can tell two
## listings apart without comparing the directory handle.
Folder : { revision : U64, name : Str, directory : Gui.FilesDirRead, captures : List(Capture.Listing) }

Status : [Busy(U64), Failed({ message : Str, remedy : Str }), Ready]

View : [Overview, Interactions, Frames, Timeline, Spec, Memory, Health, Compare, Scaling]

## A table's order: the column index and its direction.
Sort : { column : U64, descending : Bool }

## The cycle list shows every trigger of the phase, or one trigger and patch
## kind chosen from the triggers table, and optionally only the cycles in one
## duration bucket chosen from the distribution.
Filter : Capture.Scope

## The part of a long table a list holds: `rows` from the row `offset`, and
## the request that read them, which a memoized list compares instead of the
## rows themselves.
Window(a) : { offset : U64, rows : List(a), read : U64 }

## The cycles of one phase and filter the cycle list holds.
Cycles : { phase : Str, filter : Filter, window : Window(Capture.Cycle) }

## The steps of one run the step list holds.
Steps : { run : I64, window : Window(Capture.Step) }

## A page read in flight: its request and the row it starts at.
Reading : [None, Some({ id : U64, offset : U64 })]

## The frame strip on screen and the request that read it, which a memoized
## chart compares instead of its bars.
Strip : { strip : Capture.Strip, read : U64 }

## The span of the clock the timeline shows, the capture it was read from, and
## the request that read it.
Clock : { of : U64, window : Timeline.Window, read : U64 }

## Where a person is: the view, what it shows, what is selected in it, and
## where its lists were last brought to. Going back or forward returns here.
Place : {
	view : View,
	phase : Str,
	filter : Filter,
	run : I64,
	inspected : [None, Some(Capture.Inspected)],
	step_focus : [None, Some(I64)],
	family_focus : [None, Some(Str)],
	frame : [None, Some(Capture.FrameDetail)],
	cycle_scroll : [None, Some(Gui.ScrollRequest)],
	step_scroll : [None, Some(Gui.ScrollRequest)],
}

## The command palette: closed, or open with the query typed so far and the
## result Enter chooses.
Palette : [Closed, Open({ query : Str, highlight : U64 })]

## What a view inside a component boundary asks of the application as a whole:
## work that needs a handle only the root holds, or a change a sibling view
## must show. A boundary forwards it by delegation, and the root fulfils it.
Request : [
	Open(Str),
	Inspect(Capture.Cycle),
	ShowStep(I64, I64),
	SelectRun(I64),
	Show(View),
	ShowFamily(Str),
	CloseCapture,
	SetPhase(Str),
	FilterTrigger(Str, Str),
	## Read the page of the listed cycles, or of the selected run's steps,
	## that starts at a row.
	ReadCycles(U64),
	ReadSteps(U64),
	## Bring a row of the cycle list into view, reading its page if needed.
	JumpToCycle(U64, Gui.RowAlign),
	## Comparison and scaling: the open capture becomes the baseline, a
	## capture of the folder becomes the A/A capture, or the chosen captures
	## are read as a scaling set.
	SetBaseline,
	ClearBaseline,
	ChooseNoise(Str),
	ClearNoise,
	BuildScaling,
	## Show only the cycles of the list's scope in one duration bucket, which
	## holds a count of cycles; the same bucket again shows the whole scope.
	FilterBucket(I64, I64),
	## Read one frame's own work.
	SelectFrame(Capture.Bar),
	## Read the frame strip of a span of frames from a row.
	ShowFrames(I64, I64),
	## Read the timeline of a span of the clock, in nanoseconds from an instant.
	ShowTimeline(I64, I64),
	## Open a cycle in the Interactions inspector from another view.
	InspectCycle(Capture.Cycle),
	## Jumps, each remembered so Back returns from it: a view, one trigger's
	## cycles, a cycle of the selected run by its ordinal, and the cycle a
	## number of rows from the one inspected in the cycle list.
	Visit(View),
	ShowTrigger({ phase : Str, trigger : Str, patch_kind : Str }),
	FindCycle(I64),
	InspectAdjacent(I64),
	## Return to the place before the last jump, or to the one Back left.
	Back,
	Forward,
	## Put a table on the clipboard as Markdown.
	Copy({ name : Str, rows : U64, markdown : Str }),
]

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
	cycles : Cycles,
	cycles_reading : Reading,
	cycle_scroll : [None, Some(Gui.ScrollRequest)],
	steps : Steps,
	steps_reading : Reading,
	step_scroll : [None, Some(Gui.ScrollRequest)],
	family_focus : [None, Some(Str)],
	## The capture every view is compared against, the A/A capture that
	## bounds noise, and the scaling set. Each holds a connection of its own.
	baseline : [None, Some(Capture.Opened)],
	noise : [None, Some(Scaling.Member)],
	scaling : Scaling.Selection,
	## The frame budget, in hertz, frames are drawn against.
	budget : I64,
	strip : Strip,
	strip_reading : Reading,
	## The strip column and the distribution bucket under the pointer.
	frame_hover : [None, Some(I64)],
	bucket_hover : [None, Some(I64)],
	frame : [None, Some(Capture.FrameDetail)],
	## The timeline on screen, and the mark under the pointer.
	clock : Clock,
	clock_reading : Reading,
	clock_hover : [None, Some(I64)],
	palette : Palette,
	## The places jumped from, for Back and Forward.
	history : History.Trail(Place),
	## Moves keyboard focus into the cycle inspector once for each new value.
	inspector_focus : U64,
	## What the last copy put on the clipboard.
	copied : [None, Some(Str)],
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
	Window(a) : Window(a)
	Cycles : Cycles
	Steps : Steps
	Reading : Reading
	Strip : Strip
	Clock : Clock
	Place : Place
	Palette : Palette

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
		cycles: { phase: "", filter: All, window: empty_window },
		cycles_reading: None,
		cycle_scroll: None,
		steps: { run: 0, window: empty_window },
		steps_reading: None,
		step_scroll: None,
		family_focus: None,
		baseline: None,
		noise: None,
		scaling: Scaling.empty,
		budget: 60,
		strip: { strip: { start: 0, span: 0, total: 0, bars: [] }, read: 0 },
		strip_reading: None,
		frame_hover: None,
		bucket_hover: None,
		frame: None,
		clock: no_clock,
		clock_reading: None,
		clock_hover: None,
		palette: Closed,
		history: History.empty,
		inspector_focus: 0,
		copied: None,
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

	## A phase chosen where no list of cycles is shown, such as in Memory.
	set_phase : State, Str -> State
	set_phase = |state, phase| { ..state, phase, filter: All }

	## The page of the cycle list, or of the step list, a viewport showing
	## `visible` needs read, if the rows it holds and the read in flight do not
	## already cover it.
	cycles_wanted : State, Gui.EventVisibleRows -> [None, Some(U64)]
	cycles_wanted = cycles_wanted

	steps_wanted : State, Gui.EventVisibleRows -> [None, Some(U64)]
	steps_wanted = |state, visible| wanted(state.steps.window, state.steps_reading, visible, run_step_count(state))

	## The cycles the list holds for the phase and filter on screen; any other
	## phase's or filter's are not shown while this one's are read.
	listed_cycles : State -> Window(Capture.Cycle)
	listed_cycles = listed_cycles

	## The groups of the triggers table whose cycles the list shows.
	listed_triggers : State, Capture.Opened -> List(Capture.Trigger)
	listed_triggers = listed_triggers

	## How many cycles the phase and filter hold, from the triggers table,
	## which counts every one of them.
	cycle_total : State -> U64
	cycle_total = cycle_total

	## How many steps the selected run holds.
	run_step_count : State -> U64
	run_step_count = run_step_count

	## The row at an index of a window, if the window holds it.
	row_at : Window(a), U64 -> [None, Some(a)]
	row_at = row_at

	close_inspector : State -> State
	close_inspector = |state| { ..state, inspected: None }

	## The trigger and patch kind a filter holds to, whether or not it also
	## holds to a duration bucket.
	within : Filter -> Capture.Only
	within = within

	choose : State -> Gui.Action(State)
	choose = choose

	choose_file : State -> Gui.Action(State)
	choose_file = choose_file

	## The triggers table's |Δ| column, its order while a baseline applies.
	delta_column : U64
	delta_column = delta_column

	## Add a capture of the folder to the scaling set, or take it out.
	toggle_scaling : State, Str -> State
	toggle_scaling = |state, name| { ..state, scaling: Scaling.toggle(state.scaling, name) }

	## Every view, in the order the rail and the view shortcuts give them.
	views : List(View)
	views = [Overview, Interactions, Frames, Timeline, Spec, Memory, Health, Compare, Scaling]

	view_name : View -> Str
	view_name = view_name

	## Open the command palette with an empty query.
	open_palette : State -> State
	open_palette = |state| { ..state, palette: Open({ query: "", highlight: 0 }) }

	## Whether Back or Forward has somewhere to go.
	can_go_back : State -> Bool
	can_go_back = |state| !state.history.back.is_empty()

	can_go_forward : State -> Bool
	can_go_forward = |state| !state.history.forward.is_empty()
}

view_name : View -> Str
view_name = |view| match view {
	Overview => "Overview"
	Interactions => "Interactions"
	Frames => "Frames"
	Timeline => "Timeline"
	Spec => "Spec"
	Memory => "Memory"
	Health => "Health"
	Compare => "Compare"
	Scaling => "Scaling"
}

## Where the person is now.
here : State -> Place
here = |state| {
	view: state.view,
	phase: state.phase,
	filter: state.filter,
	run: state.run,
	inspected: state.inspected,
	step_focus: state.step_focus,
	family_focus: state.family_focus,
	frame: state.frame,
	cycle_scroll: state.cycle_scroll,
	step_scroll: state.step_scroll,
}

## Leave the current place for somewhere new, so Back can return to it.
remember : State -> State
remember = |state| { ..state, history: History.push(state.history, here(state)) }

## A scroll request asked again, so the list moves to it again.
again : [None, Some(Gui.ScrollRequest)], U64 -> [None, Some(Gui.ScrollRequest)]
again = |request, serial| match request {
	Some(held) => Some({ ..held, serial })
	None => None
}

## Return to a place: its view, selection, and list positions. A list whose
## rows are not held for that place is read again, from the page its scroll
## request reaches.
restore : State, Place -> Gui.Action(State)
restore = |state, place| {
	serial = state.next_request
	moved = {
		..state,
		next_request: serial + 1,
		view: place.view,
		phase: place.phase,
		filter: place.filter,
		inspected: place.inspected,
		step_focus: place.step_focus,
		family_focus: place.family_focus,
		frame: place.frame,
		cycle_scroll: again(place.cycle_scroll, serial),
		step_scroll: again(place.step_scroll, serial),
	}
	scrolled_to = |request| match request {
		Some(held) => held.row
		None => 0
	}
	if place.run != state.steps.run {
		focus = match place.step_focus {
			Some(ordinal) => Some(ordinal.to_u64_wrap())
			None => None
		}
		read_steps(moved, place.run, page_start(scrolled_to(place.step_scroll)), focus)
	} else if moved.view == Interactions and !holds_cycles(moved) {
		read_cycles(moved, page_start(scrolled_to(place.cycle_scroll)))
	} else {
		Gui.update(moved)
	}
}

## The row `delta` rows from the inspected cycle in the listed cycles, or the
## first row when none is inspected, if the list holds it.
adjacent : State, I64 -> [None, Some({ row : U64, cycle : Capture.Cycle })]
adjacent = |state, delta| {
	window = listed_cycles(state)
	current = match state.inspected {
		Some(inspected) => match window.rows.find_first_index(|cycle| cycle.id == inspected.cycle.id) {
			Ok(index) => Some((window.offset + index).to_i64_wrap())
			Err(_) => None
		}
		None => None
	}
	target = match current {
		Some(row) => row + delta
		None => if delta >= 0 window.offset.to_i64_wrap() else (window.offset + window.rows.len()).to_i64_wrap() - 1
	}
	if target < 0 {
		None
	} else {
		match row_at(window, target.to_u64_wrap()) {
			Some(cycle) => Some({ row: target.to_u64_wrap(), cycle })
			None => None
		}
	}
}

## Put a table on the clipboard through the clipboard the host granted.
copy : State, { name : Str, rows : U64, markdown : Str } -> Gui.Action(State)
copy = |state, table| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, copied: None },
		run: || match state.access.clipboard!() {
			Ok(handle) => match handle.write_text!(table.markdown) {
				Ok({}) => Copied
				Err(_) => CopyFailed
			}
			Err(_) => CopyFailed
		},
		resolve: |latest, result| match result {
			Copied => Gui.update({ ..latest, copied: Some("Copied ${table.name} as Markdown · ${table.rows.to_str()} rows") })
			CopyFailed => Gui.update({ ..latest, status: failure("Could not copy ${table.name}", "The host granted no clipboard to write. Start Observatory with --host-cap-clipboard.") })
		},
	})
}

## One cycle of the selected run by its ordinal, read and inspected in the
## Interactions view, at the phase it belongs to.
find_cycle : State, I64 -> Gui.Action(State)
find_cycle = |state, ordinal| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		run_id = state.run
		Gui.task({
			pending: { ..state, next_request: id + 1, status: Busy(id) },
			run: || match Capture.cycle_at!(opened.database, run_id, ordinal) {
				Ok(Some(cycle)) => match Capture.inspect!(opened.database, cycle) {
					Ok(inspected) => FoundCycle(inspected)
					Err(message) => CycleFailed(message)
				}
				Ok(None) => NoCycle
				Err(message) => CycleFailed(message)
			},
			resolve: |latest, outcome| match latest.status {
				Busy(active) if active == id => match outcome {
					FoundCycle(inspected) => list_cycles({ ..latest, view: Interactions, phase: inspected.cycle.phase, filter: All, inspected: Some(inspected), status: Ready, cycle_scroll: None })
					NoCycle => Gui.update({ ..latest, status: failure("No cycle ${ordinal.to_str()} in run ${run_id.to_str()}", "Cycles are numbered from 0 in each run; choose a run in Spec to look in another.") })
					CycleFailed(message) => Gui.update({ ..latest, status: failure(message, "This cycle could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

empty_window : Window(a)
empty_window = { offset: 0, rows: [], read: 0 }

no_clock : Clock
no_clock = { of: 0, window: Timeline.empty, read: 0 }

row_at : Window(a), U64 -> [None, Some(a)]
row_at = |window, index| if index < window.offset {
	None
} else {
	match window.rows.get(index - window.offset) {
		Ok(row) => Some(row)
		Err(_) => None
	}
}

## Rows either side of the viewport a window should still hold before the
## list reads again, so a person scrolling steadily meets rows already read.
margin : U64
margin = 40

## The window's first row for a viewport starting at `start`: the viewport
## sits in the middle of the page, so the rows a list mounts on either side of
## it, and scrolling either way, meet rows already read.
page_start : U64 -> U64
page_start = |start| if start > Capture.page_rows / 2 start - Capture.page_rows / 2 else 0

wanted : Window(a), Reading, Gui.EventVisibleRows, U64 -> [None, Some(U64)]
wanted = |window, reading, visible, total| {
	held_end = window.offset + window.rows.len()
	short_before = window.offset > 0 and visible.start < window.offset + margin
	needed_end = if visible.end + margin < total visible.end + margin else total
	short_after = held_end < total and needed_end > held_end
	offset = page_start(visible.start)
	in_flight = match reading {
		Some(read) => read.offset == offset
		None => False
	}
	if (short_before or short_after or window.rows.is_empty()) and !in_flight and total > 0 Some(offset) else None
}

listed_cycles : State -> Window(Capture.Cycle)
listed_cycles = |state| if holds_cycles(state) state.cycles.window else empty_window

holds_cycles : State -> Bool
holds_cycles = |state| state.cycles.phase == state.phase and state.cycles.filter == state.filter

cycles_wanted : State, Gui.EventVisibleRows -> [None, Some(U64)]
cycles_wanted = |state, visible| wanted(listed_cycles(state), state.cycles_reading, visible, cycle_total(state))

within : Filter -> Capture.Only
within = |filter| match filter {
	All => All
	Only(chosen) => Only(chosen)
	InBucket(held) => held.within
}

listed_triggers : State, Capture.Opened -> List(Capture.Trigger)
listed_triggers = |state, opened| opened.triggers.keep_if(
	|found| found.phase == state.phase
	and (
		match within(state.filter) {
			All => True
			Only(chosen) => found.trigger == chosen.trigger and found.patch_kind == chosen.patch_kind
		}
	),
)

## A bucket's count is the distribution's, which counts every cycle in it.
cycle_total : State -> U64
cycle_total = |state| match state.filter {
	InBucket(held) => held.count.to_u64_wrap()
	_ => match state.capture {
		None => 0
		Some(opened) => listed_triggers(state, opened).fold(0.I64, |total, found| total + found.count).to_u64_wrap()
	}
}

run_step_count : State -> U64
run_step_count = |state| match state.capture {
	None => 0
	Some(opened) => match opened.runs.find_first(|run| run.id == state.steps.run) {
		Ok(run) => run.steps.to_u64_wrap()
		Err(_) => 0
	}
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
		Some(Inspect(cycle)) => inspect(remember(state), cycle)
		## Open the Spec view at the step, by ordinal, that drove a cycle, with
		## the step list scrolled to it. A step's ordinal is its row.
		Some(ShowStep(run_id, ordinal)) => {
			row = ordinal.to_u64_wrap()
			read_steps({ ..remember(state), view: Spec, step_focus: Some(ordinal) }, run_id, page_start(row), Some(row))
		}
		Some(SelectRun(run_id)) => read_steps({ ..state, step_focus: None }, run_id, 0, None)
		Some(Show(view)) => list_cycles({ ..state, view, step_focus: None, family_focus: None })
		Some(ShowTimeline(start, span)) => read_clock(state, start, span)
		## A cycle pressed elsewhere opens in Interactions, in its own phase.
		Some(InspectCycle(cycle)) => inspect({ ..remember(state), view: Interactions, phase: cycle.phase, filter: if state.phase == cycle.phase state.filter else All, step_focus: None, family_focus: None }, cycle)
		## A phase chosen in Interactions reads the cycles the list then shows.
		Some(SetPhase(phase)) => list_cycles({ ..state, phase, filter: All, cycle_scroll: None })
		## Pressing the selected trigger again shows every trigger.
		Some(FilterTrigger(trigger, patch_kind)) => {
			chosen = Only({ trigger, patch_kind })
			read_cycles({ ..state, filter: if state.filter == chosen All else chosen, cycle_scroll: None, bucket_hover: None }, 0)
		}
		Some(FilterBucket(bucket, count)) => {
			scope = within(state.filter)
			filter = match state.filter {
				InBucket(held) if held.bucket == bucket => match scope {
					All => All
					Only(chosen) => Only(chosen)
				}
				_ => InBucket({ within: scope, bucket, count })
			}
			read_cycles({ ..state, filter, cycle_scroll: None }, 0)
		}
		Some(SelectFrame(bar)) => read_frame(remember(state), bar)
		Some(ShowFrames(start, span)) => read_strip(state, start, span)
		Some(ReadCycles(offset)) => read_cycles(state, offset)
		Some(ReadSteps(offset)) => read_steps(state, state.steps.run, offset, None)
		Some(JumpToCycle(row, align)) => {
			serial = state.next_request
			scrolled = { ..state, next_request: serial + 1, cycle_scroll: Some({ row, align, serial }) }
			match cycles_wanted(scrolled, { start: row, end: row + 1 }) {
				Some(offset) => read_cycles(scrolled, offset)
				None => Gui.update(scrolled)
			}
		}
		## Open Health at the family a `—` belongs to.
		Some(ShowFamily(name)) => Gui.update({ ..state, view: Health, family_focus: Some(name) })
		Some(CloseCapture) => Gui.update(close_capture(state))
		Some(SetBaseline) => Gui.update(set_baseline(state))
		Some(ClearBaseline) => Gui.update(clear_baseline(state))
		Some(ChooseNoise(name)) => match state.folder {
			Some(folder) => choose_noise(state, folder.directory, name)
			None => Gui.update(state)
		}
		Some(ClearNoise) => Gui.update({ ..state, noise: None })
		Some(Visit(view)) => list_cycles({ ..remember(state), view, step_focus: None, family_focus: None })
		Some(ShowTrigger(chosen)) => {
			filter = Only({ trigger: chosen.trigger, patch_kind: chosen.patch_kind })
			read_cycles({ ..remember(state), view: Interactions, phase: chosen.phase, filter, cycle_scroll: None, bucket_hover: None }, 0)
		}
		Some(FindCycle(ordinal)) => find_cycle(remember(state), ordinal)
		Some(InspectAdjacent(delta)) => match adjacent(state, delta) {
			Some(found) => {
				serial = state.next_request
				inspect({ ..remember(state), next_request: serial + 1, cycle_scroll: Some({ row: found.row, align: Nearest, serial }) }, found.cycle)
			}
			None => Gui.update(state)
		}
		Some(Back) => match History.back(state.history, here(state)) {
			Some(went) => restore({ ..state, history: went.history }, went.place)
			None => Gui.update(state)
		}
		Some(Forward) => match History.forward(state.history, here(state)) {
			Some(went) => restore({ ..state, history: went.history }, went.place)
			None => Gui.update(state)
		}
		Some(Copy(table)) => copy(state, table)
		Some(BuildScaling) => match state.folder {
			Some(folder) => build_scaling(state, folder.directory)
			None => Gui.update(state)
		}
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
	{ ..state, capture: None, inspected: None, status, cycles_reading: None, steps_reading: None, strip_reading: None, frame: None, frame_hover: None, bucket_hover: None, clock: no_clock, clock_reading: None, clock_hover: None, history: History.empty }
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
unreadable_remedy = "Nothing from this file is shown. Observatory reads only schema 21 captures written by the roc-gui recorder."

## Open one capture the person chooses, without a folder. The folder grant, if
## any, is kept: a single file is a separate grant beside it.
choose_file : State -> Gui.Action(State)
choose_file = |state| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match state.access.pick_file!(capture_types) {
			Ok(Chosen(selection)) => OpenedFile(first_pages!(Capture.open_file!(selection.file, selection.name)))
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

## A capture as it opens: the capture and the first page of each long list.
Loaded : { opened : Capture.Opened, phase : Str, run : I64, cycles : List(Capture.Cycle), steps : List(Capture.Step) }

## Read the first page of the cycles of the phase a capture opens at, and of
## the steps of its first run, in the task that opened it.
first_pages! : Try(Capture.Opened, Str) => Try(Loaded, Str)
first_pages! = |outcome| {
	opened = outcome?
	phase = default_phase(opened)
	run = first_run(opened)
	cycles = Capture.cycles!(opened.database, { phase, only: All, offset: 0 })?
	steps = Capture.run_steps!(opened.database, run, 0)?
	Ok({ opened, phase, run, cycles, steps })
}

## An opened capture replaces the one on screen, at its overview.
show : State, Loaded, U64 -> State
show = |latest, loaded, id| {
	window = { offset: 0, rows: loaded.cycles, read: id }
	steps = { offset: 0, rows: loaded.steps, read: id }
	{
		..latest,
		capture: Some({ ..loaded.opened, revision: id }),
		view: Overview,
		phase: loaded.phase,
		run: loaded.run,
		filter: All,
		inspected: None,
		step_focus: None,
		cycles: { phase: loaded.phase, filter: All, window },
		cycles_reading: None,
		cycle_scroll: None,
		strip: { strip: loaded.opened.strip, read: id },
		strip_reading: None,
		frame_hover: None,
		bucket_hover: None,
		frame: None,
		clock: no_clock,
		clock_reading: None,
		clock_hover: None,
		steps: { run: loaded.run, window: steps },
		steps_reading: None,
		step_scroll: None,
		family_focus: None,
		history: History.empty,
		status: Ready,
	}
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
		run: || first_pages!(Capture.open!(directory, name)),
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
					Ok(inspected) => list_cycles({ ..latest, inspected: Some(inspected), status: Ready })
					Err(message) => Gui.update({ ..latest, status: failure(message, "This cycle's detail could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

## Read the first page of the cycle list when Interactions shows a phase or
## filter whose cycles it does not hold, and the whole clock when the Timeline
## shows a capture it has not read.
list_cycles : State -> Gui.Action(State)
list_cycles = |state| if state.view == Interactions and !holds_cycles(state) {
	read_cycles(state, 0)
} else if state.view == Timeline and Some(state.clock.of) != opened_revision(state) and state.clock_reading == None {
	read_clock(state, 0, 0)
} else {
	Gui.update(state)
}

opened_revision : State -> [None, Some(U64)]
opened_revision = |state| match state.capture {
	Some(opened) => Some(opened.revision)
	None => None
}

## The timeline of a span of the clock, read through the connection the open
## capture holds. A read superseded by a later one is discarded, and the mark
## under the pointer is forgotten, since the marks now stand for other work.
read_clock : State, I64, I64 -> Gui.Action(State)
read_clock = |state, start, span| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		of = opened.revision
		Gui.task({
			pending: { ..state, next_request: id + 1, clock_reading: Some({ id, offset: 0 }) },
			run: || Timeline.read!(opened.database, start, span),
			resolve: |latest, outcome| match latest.clock_reading {
				Some(reading) if reading.id == id => match outcome {
					Ok(window) => Gui.update({ ..latest, clock: { of, window, read: id }, clock_reading: None, clock_hover: None })
					Err(message) => Gui.update({ ..latest, clock_reading: None, status: failure(message, "The timeline could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

## A page of the listed cycles, read through the connection the open capture
## holds. A page read for another phase or filter, or superseded by a later
## read, is discarded.
read_cycles : State, U64 -> Gui.Action(State)
read_cycles = |state, offset| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		phase = state.phase
		filter = state.filter
		Gui.task({
			pending: { ..state, next_request: id + 1, cycles_reading: Some({ id, offset }) },
			run: || Capture.cycles!(opened.database, { phase, only: filter, offset }),
			resolve: |latest, outcome| match latest.cycles_reading {
				Some(reading) if reading.id == id => match outcome {
					Ok(rows) => Gui.update({ ..latest, cycles: { phase, filter, window: { offset, rows, read: id } }, cycles_reading: None })
					Err(message) => Gui.update({ ..latest, cycles_reading: None, status: failure(message, "These cycles could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

## A page of one run's steps, read through the connection the open capture
## holds. `focus` is a row to bring into view once its page has been read.
read_steps : State, I64, U64, [None, Some(U64)] -> Gui.Action(State)
read_steps = |state, run_id, offset, focus| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		Gui.task({
			pending: { ..state, next_request: id + 1, steps_reading: Some({ id, offset }) },
			run: || Capture.run_steps!(opened.database, run_id, offset),
			resolve: |latest, outcome| match latest.steps_reading {
				Some(reading) if reading.id == id => match outcome {
					Ok(rows) => {
						scroll = match focus {
							Some(row) => Some({ row, align: Center, serial: id })
							None => if latest.steps.run != run_id Some({ row: 0, align: Start, serial: id }) else latest.step_scroll
						}
						Gui.update({ ..latest, steps: { run: run_id, window: { offset, rows, read: id } }, run: run_id, steps_reading: None, step_scroll: scroll })
					}
					Err(message) => Gui.update({ ..latest, steps_reading: None, status: failure(message, "The steps of this run could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

## Comparison and scaling (US-29 to US-32)

## The triggers table's column for |Δ|, by which a compared table is ordered.
delta_column : U64
delta_column = 7

## The open capture becomes the baseline, and tables order by |Δ|.
set_baseline : State -> State
set_baseline = |state| match state.capture {
	Some(opened) => { ..state, baseline: Some(opened), trigger_sort: { column: delta_column, descending: True } }
	None => state
}

clear_baseline : State -> State
clear_baseline = |state| {
	sort = if state.trigger_sort.column == delta_column { column: 4, descending: True } else state.trigger_sort
	{ ..state, baseline: None, trigger_sort: sort }
}

## A capture read by one request carries it as its revision, as an opened
## capture does, so a view compares readings rather than rows.
read_by : Scaling.Member, U64 -> Scaling.Member
read_by = |member, id| {
	opened = { ..member.opened, revision: id }
	{ ..member, opened }
}

## Read one capture of the folder as the A/A capture. Whether it may bound a
## comparison or a scaling set is judged where it is applied.
choose_noise : State, Gui.FilesDirRead, Str -> Gui.Action(State)
choose_noise = |state, directory, name| {
	id = state.next_request
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || Scaling.load!(directory, name),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(member) => Gui.update({ ..latest, noise: Some(read_by(member, id)), status: Ready })
				Err(message) => Gui.update({ ..latest, status: failure(message, "The A/A capture could not be read.") })
			}
			_ => Gui.none
		},
	})
}

## Read every chosen capture of the folder, each through a connection of its
## own. The set's gate is judged from what was read.
build_scaling : State, Gui.FilesDirRead -> Gui.Action(State)
build_scaling = |state, directory| {
	id = state.next_request
	names = state.scaling.chosen
	Gui.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || Scaling.load_all!(directory, names),
		resolve: |latest, outcome| match latest.status {
			Busy(active) if active == id => match outcome {
				Ok(members) => Gui.update({ ..latest, scaling: { chosen: names, members: members.map(|member| read_by(member, id)), read: id }, status: Ready })
				Err(message) => Gui.update({ ..latest, status: failure(message, "A capture of the scaling set could not be read.") })
			}
			_ => Gui.none
		},
	})
}

## One frame's own work, read through the connection the open capture holds.
read_frame : State, Capture.Bar -> Gui.Action(State)
read_frame = |state, bar| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		Gui.task({
			pending: { ..state, next_request: id + 1, status: Busy(id) },
			run: || Capture.frame!(opened.database, bar),
			resolve: |latest, outcome| match latest.status {
				Busy(active) if active == id => match outcome {
					Ok(detail) => Gui.update({ ..latest, frame: Some(detail), status: Ready })
					Err(message) => Gui.update({ ..latest, status: failure(message, "This frame's work could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}

## The frame strip of a span of frames. A strip superseded by a later read is
## discarded, and the column under the pointer is forgotten, since it now
## stands for other frames.
read_strip : State, I64, I64 -> Gui.Action(State)
read_strip = |state, start, span| match state.capture {
	None => Gui.update(state)
	Some(opened) => {
		id = state.next_request
		Gui.task({
			pending: { ..state, next_request: id + 1, strip_reading: Some({ id, offset: start.to_u64_wrap() }) },
			run: || Capture.strip!(opened.database, start, span),
			resolve: |latest, outcome| match latest.strip_reading {
				Some(reading) if reading.id == id => match outcome {
					Ok(strip) => Gui.update({ ..latest, strip: { strip, read: id }, strip_reading: None, frame_hover: None })
					Err(message) => Gui.update({ ..latest, strip_reading: None, status: failure(message, "These frames could not be read from the open capture.") })
				}
				_ => Gui.none
			},
		})
	}
}
