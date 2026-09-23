## Everything Observatory reads from a capture, and the rules it applies to what
## it reads. Observatory owns these queries: it opens the `.rgstats` database
## read-only and asks its tables directly, so the evidence-status rules are
## stated here, beside the SQL that depends on them.
import pf.Gui

## One `metadata` row.
Entry : { key : Str, value : Str }

## One `measurement_status` row: the family every number belongs to.
Family : { name : Str, detail : Str, status : Str, reason : Str, rows : I64, omitted : I64 }

## One `recording_gaps` row.
Gap : { family : Str, lost : I64, reason : Str }

## The single `recorder_health` row.
Health : {
	transactions : I64,
	queue_high_water : I64,
	output_bytes : I64,
	omitted_events : I64,
	rows_written : I64,
	writer_failed : I64,
	output_limited : I64,
	drain_ns : I64,
}

## One `runs` row with its step tallies.
Run : { id : I64, phase : Str, sample : [None, Some(I64)], outcome : Str, diagnostic : Str, steps : I64, failed : I64 }

## One `steps` row. Absent columns stay absent rather than becoming zero.
Step : {
	run_id : I64,
	ordinal : I64,
	line : I64,
	kind : Str,
	role : Str,
	status : Str,
	duration : [None, Some(I64)],
	expected_count : [None, Some(I64)],
	observed_count : [None, Some(I64)],
	expected_patch : Str,
	observed_patch : Str,
	diagnostic : Str,
}

## Cycles grouped by phase, trigger, and patch kind. Durations are nanoseconds.
Trigger : { phase : Str, trigger : Str, patch_kind : Str, count : I64, min : I64, median : I64, max : I64, iqr : I64 }

## The median cycle of one measurement phase.
PhaseMedian : { phase : Str, count : I64, median : I64 }

## Component comparisons and skips over the cycles of one phase whose component
## work was recorded.
SkipRate : { phase : Str, skipped : I64, compared : I64 }

## Drawn frames, and those whose host-owned stages together exceeded 16.7 ms.
Frames : { drawn : I64, over_budget : I64 }

## A frame budget a frame's host-owned stages are compared against, and the
## drawn frames that exceeded it.
Budget : { hz : I64, over : I64 }

## One column of the frame strip. A column stands for `frames` consecutive
## frames and draws the costliest of them, by the sum of its host-owned
## stages, so a slow frame is never averaged away.
Bar : { column : I64, frames : I64, id : I64, run_id : I64, ordinal : I64, layout : I64, prepaint : I64, paint : I64 }

## The frame strip: `span` frames from row `start` of every drawn frame in
## run and ordinal order, of `total`.
Strip : { start : I64, span : I64, total : I64, bars : List(Bar) }

## One metric and node kind of `gpui_native_work` over every drawn frame.
NativeTotal : { metric : I64, kind : I64, total : I64, max : I64 }

## One metric of `gpui_frame_work` over every drawn frame.
WorkTotal : { metric : I64, total : I64, max : I64 }

## One drawn frame, the native and GPUI-owned work recorded for it, and the
## cycles its owner recorded it was the first to draw. A missing native row is
## zero only because the frame itself was recorded.
FrameDetail : {
	id : I64,
	run_id : I64,
	ordinal : I64,
	layout : I64,
	prepaint : I64,
	paint : I64,
	native : List({ metric : I64, kind : I64, count : I64 }),
	work : List({ metric : I64, count : I64 }),
	causes : List(Cycle),
}

## One virtual list: its number of recorded passes, its last pass, and the most
## entities any pass materialised.
ListRow : { list_id : I64, passes : I64, visible : I64, materialized : I64, recycled : I64, live : I64, most : I64 }

## One column of the list-pass chart: the pass that materialised the most of
## the passes the column stands for.
Pass : { column : I64, list_id : I64, visible : I64, materialized : I64 }

## Cycles of one phase, trigger, and patch kind whose durations fall in one
## octave bucket.
Bucket : { phase : Str, trigger : Str, patch_kind : Str, bucket : I64, count : I64 }

## The cycles a list reads: every trigger of a phase, or one trigger and patch
## kind, and optionally only those in one duration bucket.
Only : [All, Only({ trigger : Str, patch_kind : Str })]
Scope : [All, Only({ trigger : Str, patch_kind : Str }), InBucket({ within : Only, bucket : I64, count : I64 })]

## The facts a verdict is judged from.
Trust : {
	final_state : Str,
	clean_shutdown : Str,
	gaps : I64,
	unfinalized : I64,
	partial : Str,
	health : [None, Some({ writer_failed : I64, output_limited : I64, omitted : I64 })],
}

## How far a capture may be trusted. `Unsupported` captures are refused before
## any of their tables are read. `Withheld` is a capture not yet finalised,
## which has no verdict until its recorder decides the families it rests on.
Verdict : [Complete, Partial(Str), Untrusted(Str), Unsupported(Str), Withheld(Str)]

## What the capture list shows for one file. `capture_id` names the capture a
## file holds, so a file replaced by another capture is told from one that grew.
Listing : { name : Str, capture_id : Str, application : Str, spec : Str, backend : Str, scale : Str, detail : Str, verdict : Verdict }

## How far a capture being recorded has been read: the largest id of each
## append-only table, the runs that have ended, and the finalisation and
## identity keys. Rows past these ids are the ones written since.
Progress : { cycles : I64, frames : I64, steps : I64, ended : I64, final_state : Str, capture_id : Str }

## One cycle in the slowest-cycles list. Durations are nanoseconds and every
## one is NOT NULL in the schema.
Cycle : {
	id : I64,
	run_id : I64,
	ordinal : I64,
	step_ordinal : [None, Some(I64)],
	phase : Str,
	trigger : Str,
	patch_kind : Str,
	duration : I64,
	callback : I64,
	validate : I64,
	apply : I64,
	target : Target,
}

## The element an interactive cycle reached (E4): its node kind and a hash of
## its place in the mounted graph. Neither names application text. `None` is a
## cycle no element caused, such as a task completion, or one whose target the
## recorder did not see.
Target : [None, Some({ kind : Str, identity : Str })]

## One `roc_work_spans` row: a span's time and the allocations made inside it.
Span : {
	kind : Str,
	duration : I64,
	alloc_calls : I64,
	allocated_bytes : I64,
	dealloc_calls : I64,
	realloc_calls : I64,
	reallocated_bytes : I64,
}

## A positive `component_work_counts` row.
Work : { kind : I64, count : I64 }

## A named graph counter of one cycle.
Counter : { name : Str, value : I64 }

## Everything the cycle inspector shows about one cycle.
Inspected : {
	cycle : Cycle,
	graph_apply : I64,
	gpui_apply : [None, Some(I64)],
	roc_work_valid : Bool,
	component_work_recorded : Bool,
	graph : List(Counter),
	keyed : List(Counter),
	spans : List(Span),
	work : List(Work),
	step_line : [None, Some(I64)],
}

## The waterfall's derived parts. `callback_rest` is the callback not covered
## by a span, `apply_rest` the apply not covered by graph or GPUI apply (absent
## when GPUI apply was not recorded), and `cycle_rest` the cycle not covered by
## callback, validate, or apply.
Decomposition : {
	spans_total : I64,
	callback_rest : I64,
	apply_rest : [None, Some(I64)],
	cycle_rest : I64,
	sum : I64,
	balanced : Bool,
}

## Allocations inside one span kind over the cycles of one trigger. Means are
## over every cycle of the trigger with valid spans, so a cycle that never
## entered the span counts as zero.
TriggerAlloc : {
	phase : Str,
	trigger : Str,
	span : Str,
	cycles : I64,
	calls_mean : I64,
	calls_max : I64,
	calls_total : I64,
	bytes_mean : I64,
	bytes_max : I64,
	bytes_total : I64,
}

## One run's process resources and Roc allocation lifecycle, each the change
## from the run's start to its end. A run that never ended has none.
Resources : {
	run_id : I64,
	phase : Str,
	sample : [None, Some(I64)],
	cpu_user : [None, Some(I64)],
	cpu_system : [None, Some(I64)],
	peak_rss : [None, Some(I64)],
	current_rss : [None, Some(I64)],
	alloc_calls : [None, Some(I64)],
	alloc_bytes : [None, Some(I64)],
	dealloc_calls : [None, Some(I64)],
	realloc_calls : [None, Some(I64)],
	realloc_bytes : [None, Some(I64)],
}

## A capture that passed the schema gate. Everything but its long tables is
## read when it opens; steps and cycles are read a page at a time through the
## held connection, as the lists that show them reach them.
## `revision` names one reading of the capture: the request that produced it.
## Two readings with the same revision hold the same values, which is what a
## memoized view compares instead of the rows themselves.
Opened : {
	revision : U64,
	name : Str,
	database : Gui.SqliteDb,
	metadata : List(Entry),
	families : List(Family),
	gaps : List(Gap),
	health : [None, Some(Health)],
	runs : List(Run),
	triggers : List(Trigger),
	medians : List(PhaseMedian),
	skips : List(SkipRate),
	frames : Frames,
	budgets : List(Budget),
	strip : Strip,
	native : List(NativeTotal),
	work : List(WorkTotal),
	lists : List(ListRow),
	passes : List(Pass),
	buckets : List(Bucket),
	allocations : List(TriggerAlloc),
	resources : List(Resources),
	verdict : Verdict,
}

Capture := [].{
	Entry : Entry
	Family : Family
	Gap : Gap
	Health : Health
	Run : Run
	Step : Step
	Trigger : Trigger
	PhaseMedian : PhaseMedian
	SkipRate : SkipRate
	Frames : Frames
	Budget : Budget
	Bar : Bar
	Strip : Strip
	NativeTotal : NativeTotal
	WorkTotal : WorkTotal
	FrameDetail : FrameDetail
	ListRow : ListRow
	Pass : Pass
	Bucket : Bucket
	Only : Only
	Scope : Scope
	Trust : Trust
	Verdict : Verdict
	Listing : Listing
	Progress : Progress
	Opened : Opened
	Cycle : Cycle
	Target : Target
	Span : Span
	Work : Work
	Counter : Counter
	Inspected : Inspected
	Decomposition : Decomposition
	TriggerAlloc : TriggerAlloc
	Resources : Resources

	## A cycle's target from its two columns at `index`, as `decode_cycle`
	## reads it.
	target_at : List(Gui.SqliteValue), U64 -> Target
	target_at = target_at

	## A cycle's target as every view names it.
	target_caption : Cycle -> Str
	target_caption = target_caption

	## The one schema this application reads.
	supported_schema : Str
	supported_schema = "23"

	## Read enough of one file to list it: identity and a verdict.
	summarize! : Gui.FilesDirRead, Str => Listing
	summarize! = summarize!

	## Open one capture, refuse it unless it is schema 23, and read every table
	## the views present.
	open! : Gui.FilesDirRead, Str => Try(Opened, Str)
	open! = open!

	## Open one chosen capture file, with the same refusal and reads as `open!`.
	open_file! : Gui.FilesFileRead, Str => Try(Opened, Str)
	open_file! = open_file!

	## How many rows one read of a long table returns: several screens of a
	## list, so scrolling reads again only every few screens.
	page_rows : U64
	page_rows = page_rows

	## At most `page_rows` steps of one run, from the step whose ordinal is
	## `from`. Ordinals number a run's steps from zero, so a step's ordinal is
	## its row in the run's list.
	run_steps! : Gui.SqliteDb, I64, U64 => Try(List(Step), Str)
	run_steps! = run_steps!

	## At most `page_rows` cycles of one phase, slowest first, from the
	## `offset`th: every trigger's, or one trigger and patch kind's.
	cycles! : Gui.SqliteDb, { phase : Str, only : Scope, offset : U64 } => Try(List(Cycle), Str)
	cycles! = cycles!

	## The cycle of a run with an ordinal, whatever its phase, if there is one.
	cycle_at! : Gui.SqliteDb, I64, I64 => Try([None, Some(Cycle)], Str)
	cycle_at! = |database, run_id, ordinal| {
		found = database.query_with!(cycle_at_sql, [Integer(run_id), Integer(ordinal)]) ? |error| Gui.Sqlite.detail(error)
		match found.rows.first() {
			Ok(row) => Ok(Some(decode_cycle(row)))
			Err(_) => Ok(None)
		}
	}

	## How many columns the frame strip and the list-pass chart draw.
	columns : I64
	columns = columns

	## The budgets a frame can be compared against, in hertz.
	budget_rates : List(I64)
	budget_rates = budget_rates

	## A frame budget in nanoseconds.
	budget_ns : I64 -> I64
	budget_ns = |hz| 1000000000 / hz

	## The frame strip of `span` frames from row `start`; a `span` of zero is
	## every frame from `start`.
	strip! : Gui.SqliteDb, I64, I64 => Try(Strip, Str)
	strip! = strip!

	## One frame's own work.
	frame! : Gui.SqliteDb, Bar => Try(FrameDetail, Str)
	frame! = frame!

	## The native node kinds, the keyed container, and the popover, by numeric kind.
	node_kinds : List(Str)
	node_kinds = ["canvas", "button", "checkbox", "textarea", "image", "column", "dialog", "panel", "row", "scroll", "virtual item", "virtual list", "text input", "text", "styled text", "boundary", "keyed container", "popover"]

	## The nineteen GPUI frame-work metrics, by numeric metric, and the group
	## each belongs to.
	work_metrics : List({ name : Str, group : [Replayed, Fresh, Moved] })
	work_metrics = work_metrics

	## The share of a frame's scene operations GPUI replayed from its cache
	## rather than built fresh: `Some` percent, or `None` for a frame with no
	## scene operation at all.
	replay_share : List({ metric : I64, count : I64 }) -> [None, Some(I64)]
	replay_share = replay_share

	## The duration range of an octave bucket, in nanoseconds: at least `low`
	## and below `high`.
	bucket_range : I64 -> { low : I64, high : I64 }
	bucket_range = bucket_range

	## How many octave buckets there are.
	bucket_count : I64
	bucket_count = bucket_count

	## The bucket a duration falls in.
	bucket_of : I64 -> I64
	bucket_of = bucket_of

	## Read one cycle's spans, component work, graph work, and step.
	inspect! : Gui.SqliteDb, Cycle => Try(Inspected, Str)
	inspect! = inspect!

	## The five Roc work spans, in the order the callback decomposes into them.
	span_kinds : List(Str)
	span_kinds = ["routing", "application_update", "application_render", "component_comparison", "platform_lowering"]

	## The eleven component work kinds, indexed by their numeric kind.
	work_kinds : List(Str)
	work_kinds = ["rendered", "compared", "skipped", "mounted", "retired", "registry_visits", "ancestor_invalidations", "projection_gets", "projection_sets", "keyed_order_visits", "keyed_snapshot_items"]

	## A span's recorded row. In a cycle whose span evidence is valid, a span
	## with no row did not run.
	span : Inspected, Str -> [Missing, Found(Span)]
	span = |inspected, kind| match inspected.spans.find_first(|found| found.kind == kind) {
		Ok(found) => Found(found)
		Err(_) => Missing
	}

	## A component work count. Absent is zero only when the cycle's component
	## work was recorded.
	work_count : Inspected, I64 -> [None, Some(I64)]
	work_count = work_count

	decompose : Inspected -> Decomposition
	decompose = decompose

	## The rule on the Health sheet.
	judge : Trust -> Verdict
	judge = judge

	## The rule, in words, exactly as `judge` applies it.
	rule : Str
	rule = "Withheld until the capture is finalised: the families a verdict rests on are decided only then, and a capture still being recorded reads the same as one whose recorder stopped. Untrusted when a finalised capture shut down uncleanly, lost events, hit its output limit, had a writer failure, or recorded a gap. Partial when any measurement family is partial. Otherwise complete: not_recorded and unavailable families are declared absences, not losses."

	## What a verdict that needs finalisation says while it is withheld.
	unfinalised : Str
	unfinalised = unfinalised

	## Whether the capture's recorder has finalised it.
	finalised : Opened -> Bool
	finalised = |opened| metadata(opened, "final_state") == "complete"

	## How far a capture has been written, read in one statement.
	progress! : Gui.SqliteDb => Try(Progress, Str)
	progress! = progress!

	## The identity of the capture a file holds, read through a connection of
	## its own.
	identity! : Gui.SqliteDb => Try(Str, Str)
	identity! = |database| {
		found = rows!(database, "SELECT value FROM metadata WHERE key = 'capture_id'")?
		match found.first() {
			Ok(row) => Ok(text_at(row, 0))
			Err(_) => Ok("")
		}
	}

	## Read every table the views present again, through a held connection.
	read! : Gui.SqliteDb, Str => Try(Opened, Str)
	read! = read!

	metadata : Opened, Str -> Str
	metadata = metadata

	family : Opened, Str -> [Missing, Found(Family)]
	family = family

	## A family whose values may be shown. Anything else renders `—`.
	complete : Opened, Str -> Bool
	complete = |opened, name| match family(opened, name) {
		Found(found) => found.status == "complete"
		Missing => False
	}

	## Why a family's values are absent, for the line beside a `—`.
	absence : Opened, Str -> Str
	absence = |opened, name| match family(opened, name) {
		Found(found) => "${found.name} ${found.status}: ${found.reason}"
		Missing => "${name} is not recorded in this capture"
	}

	verdict_word : Verdict -> Str
	verdict_word = |verdict| match verdict {
		Complete => "complete"
		Partial(_) => "partial"
		Untrusted(_) => "untrusted"
		Unsupported(_) => "unsupported"
		Withheld(_) => "withheld"
	}

	verdict_reason : Verdict -> Str
	verdict_reason = |verdict| match verdict {
		Complete => "every family finalised without recorded loss"
		Partial(reason) => reason
		Untrusted(reason) => reason
		Unsupported(reason) => reason
		Withheld(reason) => reason
	}

	## Refuse any capture whose schema is not the one this application reads.
	schema_gate : Str -> Try({}, Str)
	schema_gate = schema_gate
}

work_count : Inspected, I64 -> [None, Some(I64)]
work_count = |inspected, kind| if inspected.component_work_recorded {
	match inspected.work.find_first(|found| found.kind == kind) {
		Ok(found) => Some(found.count)
		Err(_) => Some(0)
	}
} else {
	None
}

## The parts balance when no remainder is negative, so that callback, validate,
## apply, and the unattributed rest sum exactly to the cycle, and the spans fit
## inside the callback.
decompose : Inspected -> Decomposition
decompose = |inspected| {
	cycle = inspected.cycle
	spans_total = inspected.spans.fold(0, |total, found| total + found.duration)
	callback_rest = cycle.callback - spans_total
	apply_rest = match inspected.gpui_apply {
		Some(gpui) => Some(cycle.apply - inspected.graph_apply - gpui)
		None => None
	}
	cycle_rest = cycle.duration - cycle.callback - cycle.validate - cycle.apply
	spans_fit = !inspected.roc_work_valid or callback_rest >= 0
	apply_fits = match apply_rest {
		Some(rest) => rest >= 0
		None => inspected.graph_apply <= cycle.apply
	}
	sum = cycle.callback + cycle.validate + cycle.apply + cycle_rest
	{ spans_total, callback_rest, apply_rest, cycle_rest, sum, balanced: spans_fit and apply_fits and cycle_rest >= 0 and sum == cycle.duration }
}

## An initialization cycle as a GPUI window records it: most of the cycle is
## outside the callback, validate, and apply, and that remainder is explicit.
sample_inspected : Inspected
sample_inspected = {
	cycle: { id: 1, run_id: 1, ordinal: 0, step_ordinal: None, phase: "interactive", trigger: "init", patch_kind: "mount", duration: 47776342, callback: 521128, validate: 17894, apply: 39546, target: None },
	graph_apply: 7555,
	gpui_apply: Some(31991),
	roc_work_valid: True,
	component_work_recorded: True,
	graph: [],
	keyed: [],
	spans: [{ kind: "platform_lowering", duration: 222282, alloc_calls: 77, allocated_bytes: 41432, dealloc_calls: 84, realloc_calls: 0, reallocated_bytes: 0 }],
	work: [{ kind: 0, count: 1 }],
	step_line: None,
}

expect decompose(sample_inspected) == { spans_total: 222282, callback_rest: 298846, apply_rest: Some(0), cycle_rest: 47197774, sum: 47776342, balanced: True }
expect decompose({ ..sample_inspected, gpui_apply: None }).apply_rest == None
expect decompose({ ..sample_inspected, spans: [{ kind: "routing", duration: 600000, alloc_calls: 0, allocated_bytes: 0, dealloc_calls: 0, realloc_calls: 0, reallocated_bytes: 0 }] }).balanced == False
expect decompose({ ..sample_inspected, roc_work_valid: False, spans: [] }).balanced == True
expect work_count(sample_inspected, 0) == Some(1)
expect work_count(sample_inspected, 2) == Some(0)
expect work_count({ ..sample_inspected, component_work_recorded: False }, 0) == None

schema_gate : Str -> Try({}, Str)
schema_gate = |version| if version == "23" {
	Ok({})
} else if Str.is_empty(version) {
	Err("This file records no schema version; Observatory reads schema 23")
} else {
	Err("Schema ${version} is not supported; Observatory reads schema 23")
}

metadata : Opened, Str -> Str
metadata = |opened, key| lookup(opened.metadata, key)

lookup : List(Entry), Str -> Str
lookup = |entries, key| match entries.find_first(|entry| entry.key == key) {
	Ok(entry) => entry.value
	Err(_) => ""
}

family : Opened, Str -> [Missing, Found(Family)]
family = |opened, name| match opened.families.find_first(|found| found.name == name) {
	Ok(found) => Found(found)
	Err(_) => Missing
}

unfinalised : Str
unfinalised = "capture not yet finalised"

judge : Trust -> Verdict
judge = |trust| if trust.final_state != "complete" Withheld(unfinalised) else judge_finalised(trust)

judge_finalised : Trust -> Verdict
judge_finalised = |trust| {
	health_causes = match trust.health {
		None => ["the recorder health row is missing"]
		Some(health) => {
			writer = if health.writer_failed != 0 ["the writer failed"] else []
			limit = if health.output_limited != 0 ["output was limited"] else []
			omitted = if health.omitted != 0 ["${health.omitted.to_str()} events were omitted"] else []
			writer.concat(limit).concat(omitted)
		}
	}
	final = if trust.final_state == "complete" [] else ["not finalised (${trust.final_state})"]
	clean = if trust.clean_shutdown == "1" [] else ["unclean shutdown"]
	gaps = if trust.gaps == 0 [] else ["${trust.gaps.to_str()} recording gaps"]
	unfinalized = if trust.unfinalized == 0 [] else ["${trust.unfinalized.to_str()} families unfinalized"]
	causes = final.concat(clean).concat(health_causes).concat(gaps).concat(unfinalized)
	if !causes.is_empty() {
		Untrusted(Str.join_with(causes, "; "))
	} else if !Str.is_empty(trust.partial) {
		Partial("partial families: ${trust.partial}")
	} else {
		Complete
	}
}

expect judge({ final_state: "complete", clean_shutdown: "1", gaps: 0, unfinalized: 0, partial: "", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Complete
expect judge({ final_state: "recording", clean_shutdown: "0", gaps: 0, unfinalized: 0, partial: "", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Withheld("capture not yet finalised")
expect judge({ final_state: "complete", clean_shutdown: "0", gaps: 0, unfinalized: 0, partial: "", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Untrusted("unclean shutdown")
expect judge({ final_state: "complete", clean_shutdown: "1", gaps: 0, unfinalized: 0, partial: "timing_environment", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Partial("partial families: timing_environment")
expect schema_gate("4") == Err("Schema 4 is not supported; Observatory reads schema 23")
expect schema_gate("22") == Err("Schema 22 is not supported; Observatory reads schema 23")

## Cells. Every column read through these is declared by schema 23; a nullable
## column is read as an option so an absent value never becomes zero.
text_at : List(Gui.SqliteValue), U64 -> Str
text_at = |row, index| match row.get(index) {
	Ok(String(value)) => value
	Ok(Integer(value)) => value.to_str()
	Ok(Real(value)) => value.to_str()
	_ => ""
}

option_at : List(Gui.SqliteValue), U64 -> [None, Some(I64)]
option_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => Some(value)
	_ => None
}

## A NOT NULL integer column.
int_at : List(Gui.SqliteValue), U64 -> I64
int_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => value
	_ => 0
}

rows! : Gui.SqliteDb, Str => Try(List(List(Gui.SqliteValue)), Str)
rows! = |database, sql| match database.query!(sql) {
	Ok(result) => Ok(result.rows)
	Err(error) => Err(Gui.Sqlite.detail(error))
}

metadata_sql = "SELECT key, value FROM metadata ORDER BY key"

trust_sql = "SELECT (SELECT count(*) FROM recording_gaps), (SELECT count(*) FROM measurement_status WHERE status = 'unfinalized'), (SELECT coalesce(group_concat(name, ', '), '') FROM measurement_status WHERE status = 'partial'), writer_failed, output_limited, omitted_events FROM recorder_health WHERE id = 1"

families_sql = "SELECT name, required_detail, status, reason, rows_recorded, omitted_events FROM measurement_status ORDER BY rowid"

gaps_sql = "SELECT family, lost_count, reason FROM recording_gaps ORDER BY id"

health_sql = "SELECT transactions, queue_high_water, output_bytes, omitted_events, rows_written, writer_failed, output_limited, drain_duration_ns FROM recorder_health WHERE id = 1"

runs_sql = "SELECT r.id, r.phase, r.sample_index, r.outcome, coalesce(r.diagnostic, ''), (SELECT count(*) FROM steps s WHERE s.run_id = r.id), (SELECT count(*) FROM steps s WHERE s.run_id = r.id AND s.status = 'fail') FROM runs r ORDER BY r.id"

steps_sql = "SELECT run_id, ordinal, source_line, kind, role, status, duration_ns, expected_count, observed_count, coalesce(expected_patch_kind, ''), coalesce(observed_patch_kind, ''), coalesce(diagnostic, '') FROM steps WHERE run_id = ? AND ordinal >= ? ORDER BY ordinal"

page_rows : U64
page_rows = 200

## Warmup runs exist to be discarded, so every cycle statistic excludes them.
## Median by averaging the one or two middle ranks; interquartile range by
## nearest rank. Both are computed over every remaining cycle of the group.
triggers_sql = "WITH c AS (SELECT measurement_phase AS phase, trigger, patch_kind, duration_ns AS d, row_number() OVER (PARTITION BY measurement_phase, trigger, patch_kind ORDER BY duration_ns) AS rn, count(*) OVER (PARTITION BY measurement_phase, trigger, patch_kind) AS n FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')) SELECT phase, trigger, patch_kind, n, min(d), CAST(round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN d END)) AS INTEGER) AS median, max(d), max(CASE WHEN rn = (3 * n + 3) / 4 THEN d END) - max(CASE WHEN rn = (n + 3) / 4 THEN d END) FROM c GROUP BY phase, trigger, patch_kind ORDER BY phase, median DESC, trigger, patch_kind"

medians_sql = "WITH c AS (SELECT measurement_phase AS phase, duration_ns AS d, row_number() OVER (PARTITION BY measurement_phase ORDER BY duration_ns) AS rn, count(*) OVER (PARTITION BY measurement_phase) AS n FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')) SELECT phase, n, CAST(round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN d END)) AS INTEGER) FROM c GROUP BY phase ORDER BY phase"

## An absent kind is zero only for a cycle whose component work was recorded,
## so only those cycles are summed.
skips_sql = "SELECT c.measurement_phase, coalesce(sum(CASE w.kind WHEN 2 THEN w.count END), 0), coalesce(sum(CASE w.kind WHEN 1 THEN w.count END), 0) FROM cycles c LEFT JOIN component_work_counts w ON w.cycle_id = c.id WHERE c.component_work_recorded = 1 AND c.run_id IN (SELECT id FROM runs WHERE phase <> 'warmup') GROUP BY c.measurement_phase ORDER BY c.measurement_phase"

frames_sql = "SELECT count(*), coalesce(sum(CASE WHEN layout_request_ns + prepaint_ns + paint_ns > 16666667 THEN 1 ELSE 0 END), 0) FROM gpui_frames"

columns : I64
columns = 240

budget_rates : List(I64)
budget_rates = [30, 60, 120]

## Over-budget counts for every selectable budget, in `budget_rates` order.
budgets_sql = "SELECT coalesce(sum(CASE WHEN t > 1000000000 / 30 THEN 1 ELSE 0 END), 0), coalesce(sum(CASE WHEN t > 1000000000 / 60 THEN 1 ELSE 0 END), 0), coalesce(sum(CASE WHEN t > 1000000000 / 120 THEN 1 ELSE 0 END), 0) FROM (SELECT layout_request_ns + prepaint_ns + paint_ns AS t FROM gpui_frames)"

## Frames number from zero in run and ordinal order. Each column keeps the
## costliest of its frames: with exactly one max() aggregate, SQLite takes the
## bare columns from the row that holds the maximum.
strip_sql = "WITH f AS (SELECT id, run_id, ordinal, layout_request_ns AS l, prepaint_ns AS p, paint_ns AS q, row_number() OVER (ORDER BY run_id, ordinal) - 1 AS r FROM gpui_frames), w AS (SELECT *, (r - ?1) * ?3 / ?2 AS c FROM f WHERE r >= ?1 AND r < ?1 + ?2) SELECT c, count(*), max(l + p + q), id, run_id, ordinal, l, p, q FROM w GROUP BY c ORDER BY c"

frame_count_sql = "SELECT count(*) FROM gpui_frames"

native_sql = "SELECT metric, kind, sum(count), max(count) FROM gpui_native_work GROUP BY metric, kind ORDER BY metric, kind"

work_totals_sql = "SELECT metric, sum(count), max(count) FROM gpui_frame_work GROUP BY metric ORDER BY metric"

frame_native_sql = "SELECT metric, kind, count FROM gpui_native_work WHERE frame_id = ? ORDER BY metric, kind"

frame_work_sql = "SELECT metric, count FROM gpui_frame_work WHERE frame_id = ? ORDER BY metric"

## Only the recorded link says which cycles a frame drew.
frame_causes_sql = "SELECT c.id, c.run_id, c.ordinal, c.step_ordinal, c.measurement_phase, c.trigger, c.patch_kind, c.duration_ns, c.roc_callback_ns, c.validate_ns, c.apply_ns, c.target_kind, c.target_identity FROM gpui_frame_cycles l JOIN cycles c ON c.id = l.cycle_id WHERE l.frame_id = ? ORDER BY c.run_id, c.ordinal"

lists_sql = "WITH l AS (SELECT list_id, count(*) AS n, max(id) AS last, max(materialized_entities) AS most FROM virtual_list_frames GROUP BY list_id) SELECT l.list_id, l.n, v.visible_items, v.materialized_entities, v.recycled_entities, v.live_entities, l.most FROM l JOIN virtual_list_frames v ON v.id = l.last ORDER BY l.list_id"

## As the frame strip: each column keeps the pass that materialised the most.
passes_sql = "WITH p AS (SELECT list_id, visible_items AS v, materialized_entities AS m, row_number() OVER (ORDER BY id) - 1 AS r, count(*) OVER () AS n FROM virtual_list_frames) SELECT r * 240 / n AS c, max(m), list_id, v FROM p GROUP BY c ORDER BY c"

work_metrics : List({ name : Str, group : [Replayed, Fresh, Moved] })
work_metrics = [
	{ name: "cached prepaint subtrees", group: Replayed },
	{ name: "replayed hitboxes", group: Replayed },
	{ name: "replayed dispatch nodes", group: Replayed },
	{ name: "replayed deferred draws", group: Replayed },
	{ name: "replayed prepaint element states", group: Replayed },
	{ name: "cached paint subtrees", group: Replayed },
	{ name: "replayed scene operations", group: Replayed },
	{ name: "replayed mouse listeners", group: Replayed },
	{ name: "replayed input handlers", group: Replayed },
	{ name: "replayed cursor styles", group: Replayed },
	{ name: "replayed paint element states", group: Replayed },
	{ name: "replayed tab stops", group: Replayed },
	{ name: "fresh hitboxes", group: Fresh },
	{ name: "fresh mouse listeners", group: Fresh },
	{ name: "fresh scene operations", group: Fresh },
	{ name: "fresh element state accesses", group: Fresh },
	{ name: "element states moved", group: Moved },
	{ name: "view states rebased in prepaint", group: Moved },
	{ name: "view states rebased in paint", group: Moved },
]

replay_share : List({ metric : I64, count : I64 }) -> [None, Some(I64)]
replay_share = |work| {
	count = |metric| match work.find_first(|found| found.metric == metric) {
		Ok(found) => found.count
		Err(_) => 0
	}
	replayed = count(6)
	fresh = count(14)
	if replayed + fresh == 0 None else Some(replayed * 100 / (replayed + fresh))
}

expect replay_share([{ metric: 6, count: 3 }, { metric: 14, count: 9 }]) == Some(25)
expect replay_share([]) == None

## Octave buckets from one microsecond: bucket 0 is below 1 µs, bucket k holds
## durations of at least 2^(k-1) µs and below 2^k µs, and the last bucket holds
## every duration from 2^23 µs (about 8.4 s) up.
bucket_count : I64
bucket_count = 25

bucket_edge : I64 -> I64
bucket_edge = |k| {
	var $edge = 1000
	var $index = 0
	while $index < k {
		$edge = $edge * 2
		$index = $index + 1
	}
	$edge
}

bucket_range : I64 -> { low : I64, high : I64 }
bucket_range = |bucket| {
	low = if bucket <= 0 0 else bucket_edge(bucket - 1)
	high = if bucket >= bucket_count - 1 9223372036854775807 else bucket_edge(bucket)
	{ low, high }
}

bucket_of : I64 -> I64
bucket_of = |duration| {
	var $bucket = 0
	while $bucket < bucket_count - 1 and duration >= bucket_edge($bucket) {
		$bucket = $bucket + 1
	}
	$bucket
}

expect bucket_range(0) == { low: 0, high: 1000 }
expect bucket_range(1) == { low: 1000, high: 2000 }
expect bucket_of(999) == 0
expect bucket_of(1000) == 1
expect bucket_of(1999) == 1
expect bucket_of(16666667) == 15

## A cycle's bucket is the number of edges its duration reaches, exactly as
## `bucket_of` counts them.
bucket_expression : Str
bucket_expression = {
	var $terms = []
	var $k = 0
	while $k < bucket_count - 1 {
		$terms = $terms.append("(duration_ns >= ${bucket_edge($k).to_str()})")
		$k = $k + 1
	}
	Str.join_with($terms, " + ")
}

buckets_sql = "SELECT measurement_phase, trigger, patch_kind, ${bucket_expression} AS b, count(*) FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup') GROUP BY measurement_phase, trigger, patch_kind, b ORDER BY measurement_phase, trigger, patch_kind, b"

## Warmups are excluded, as in every cycle statistic. Ties in duration order
## by id, so a page boundary never repeats or skips a cycle.
cycle_columns = "SELECT id, run_id, ordinal, step_ordinal, measurement_phase, trigger, patch_kind, duration_ns, roc_callback_ns, validate_ns, apply_ns, target_kind, target_identity FROM cycles WHERE measurement_phase = ? AND run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')"

cycles_sql = "${cycle_columns} ORDER BY duration_ns DESC, id LIMIT -1 OFFSET ?"

cycle_at_sql = "SELECT id, run_id, ordinal, step_ordinal, measurement_phase, trigger, patch_kind, duration_ns, roc_callback_ns, validate_ns, apply_ns, target_kind, target_identity FROM cycles WHERE run_id = ? AND ordinal = ?"

trigger_cycles_sql = "${cycle_columns} AND trigger = ? AND patch_kind = ? ORDER BY duration_ns DESC, id LIMIT -1 OFFSET ?"

bucket_cycles_sql = "${cycle_columns} AND duration_ns >= ? AND duration_ns < ? ORDER BY duration_ns DESC, id LIMIT -1 OFFSET ?"

trigger_bucket_cycles_sql = "${cycle_columns} AND trigger = ? AND patch_kind = ? AND duration_ns >= ? AND duration_ns < ? ORDER BY duration_ns DESC, id LIMIT -1 OFFSET ?"

detail_sql = "SELECT graph_apply_ns, gpui_apply_ns, roc_work_valid, component_work_recorded, staged_nodes, removed_nodes, live_nodes, retained_nodes, parent_nodes_scanned, validation_visits, keyed_graph_visits, keyed_original_reads, keyed_first_touches, keyed_native_edits, keyed_item_entities_created, keyed_item_entities_retired, keyed_item_entities_moved, (SELECT s.source_line FROM steps s WHERE s.run_id = c.run_id AND s.ordinal = c.step_ordinal) FROM cycles c WHERE c.id = ?"

spans_sql = "SELECT kind, duration_ns, alloc_calls, allocated_bytes, dealloc_calls, realloc_calls, reallocated_bytes FROM roc_work_spans WHERE cycle_id = ?"

work_sql = "SELECT kind, count FROM component_work_counts WHERE cycle_id = ? ORDER BY kind"

## Only cycles whose span evidence is valid are summed, and a mean divides by
## every such cycle of the trigger.
allocations_sql = "WITH v AS (SELECT id, measurement_phase AS phase, trigger FROM cycles WHERE roc_work_valid = 1 AND run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')), n AS (SELECT phase, trigger, count(*) AS cycles FROM v GROUP BY phase, trigger) SELECT v.phase, v.trigger, s.kind, n.cycles, CAST(round(sum(s.alloc_calls) * 1.0 / n.cycles) AS INTEGER), max(s.alloc_calls), sum(s.alloc_calls), CAST(round(sum(s.allocated_bytes) * 1.0 / n.cycles) AS INTEGER), max(s.allocated_bytes), sum(s.allocated_bytes) FROM roc_work_spans s JOIN v ON v.id = s.cycle_id JOIN n ON n.phase = v.phase AND n.trigger = v.trigger GROUP BY v.phase, v.trigger, s.kind ORDER BY v.phase, sum(s.allocated_bytes) DESC, v.trigger, s.kind"

## An end column is NULL until its run ends, and so is every difference taken
## from it.
resources_sql = "SELECT id, phase, sample_index, end_cpu_user_ns - start_cpu_user_ns, end_cpu_system_ns - start_cpu_system_ns, end_max_rss_bytes, end_current_rss_bytes, end_roc_alloc_calls - start_roc_alloc_calls, end_roc_alloc_requested_bytes - start_roc_alloc_requested_bytes, end_roc_dealloc_calls - start_roc_dealloc_calls, end_roc_realloc_calls - start_roc_realloc_calls, end_roc_realloc_requested_bytes - start_roc_realloc_requested_bytes FROM runs ORDER BY id"

bound_rows! : Gui.SqliteDb, Str, I64 => Try(List(List(Gui.SqliteValue)), Str)
bound_rows! = |database, sql, value| match database.query_with!(sql, [Integer(value)]) {
	Ok(result) => Ok(result.rows)
	Err(error) => Err(Gui.Sqlite.detail(error))
}

cycles! : Gui.SqliteDb, { phase : Str, only : Scope, offset : U64 } => Try(List(Cycle), Str)
cycles! = |database, scope| {
	offset = Integer(scope.offset.to_i64_wrap())
	request = match scope.only {
		All => { sql: cycles_sql, params: [String(scope.phase), offset], rows: page_rows }
		Only(chosen) => { sql: trigger_cycles_sql, params: [String(scope.phase), String(chosen.trigger), String(chosen.patch_kind), offset], rows: page_rows }
		InBucket(held) => {
			range = bucket_range(held.bucket)
			match held.within {
				All => { sql: bucket_cycles_sql, params: [String(scope.phase), Integer(range.low), Integer(range.high), offset], rows: page_rows }
				Only(chosen) => { sql: trigger_bucket_cycles_sql, params: [String(scope.phase), String(chosen.trigger), String(chosen.patch_kind), Integer(range.low), Integer(range.high), offset], rows: page_rows }
			}
		}
	}
	page = database.page!(request) ? |error| Gui.Sqlite.detail(error)
	Ok(page.rows.map(decode_cycle))
}

decode_cycle : List(Gui.SqliteValue) -> Cycle
decode_cycle = |row| {
	id: int_at(row, 0),
	run_id: int_at(row, 1),
	ordinal: int_at(row, 2),
	step_ordinal: option_at(row, 3),
	phase: text_at(row, 4),
	trigger: text_at(row, 5),
	patch_kind: text_at(row, 6),
	duration: int_at(row, 7),
	callback: int_at(row, 8),
	validate: int_at(row, 9),
	apply: int_at(row, 10),
	target: target_at(row, 11),
}

## A cycle's target from its two nullable columns, which the schema requires
## to be present or absent together.
target_at : List(Gui.SqliteValue), U64 -> Target
target_at = |row, index| match (row.get(index), row.get(index + 1)) {
	(Ok(String(kind)), Ok(String(identity))) => Some({ kind, identity })
	_ => None
}

## How a list, the inspector, and the Timeline name a cycle's target.
## Initialization and task completions are caused by no element, so they have
## no target rather than an unrecorded one.
target_caption : Cycle -> Str
target_caption = |cycle| match cycle.target {
	Some(found) => "${found.kind} ${found.identity}"
	None => if cycle.trigger == "init" or cycle.trigger == "task" "no target" else "target not recorded"
}

expect target_caption({ ..sample_inspected.cycle, trigger: "click", target: Some({ kind: "button", identity: "00ff00ff00ff00ff" }) }) == "button 00ff00ff00ff00ff"
expect target_caption({ ..sample_inspected.cycle, trigger: "click" }) == "target not recorded"
expect target_caption(sample_inspected.cycle) == "no target"

counters : List(Gui.SqliteValue), U64, List(Str) -> List(Counter)
counters = |row, start, names| names.map_with_index(|name, index| { name, value: int_at(row, start + index) })

decode_span : List(Gui.SqliteValue) -> Span
decode_span = |row| {
	kind: text_at(row, 0),
	duration: int_at(row, 1),
	alloc_calls: int_at(row, 2),
	allocated_bytes: int_at(row, 3),
	dealloc_calls: int_at(row, 4),
	realloc_calls: int_at(row, 5),
	reallocated_bytes: int_at(row, 6),
}

inspect! : Gui.SqliteDb, Cycle => Try(Inspected, Str)
inspect! = |database, cycle| {
	details = bound_rows!(database, detail_sql, cycle.id)?
	spans = bound_rows!(database, spans_sql, cycle.id)?
	work = bound_rows!(database, work_sql, cycle.id)?
	match details.first() {
		Err(_) => Err("Cycle ${cycle.id.to_str()} is not in this capture")
		Ok(row) => Ok({
			cycle,
			graph_apply: int_at(row, 0),
			gpui_apply: option_at(row, 1),
			roc_work_valid: int_at(row, 2) == 1,
			component_work_recorded: int_at(row, 3) == 1,
			graph: counters(row, 4, ["staged", "removed", "live", "retained", "parent scanned", "validation visits"]),
			keyed: counters(row, 10, ["keyed graph visits", "original reads", "first touches", "native edits", "items created", "items retired", "items moved"]),
			spans: spans.map(decode_span),
			work: work.map(|found| { kind: int_at(found, 0), count: int_at(found, 1) }),
			step_line: option_at(row, 17),
		})
	}
}

decode_allocation : List(Gui.SqliteValue) -> TriggerAlloc
decode_allocation = |row| {
	phase: text_at(row, 0),
	trigger: text_at(row, 1),
	span: text_at(row, 2),
	cycles: int_at(row, 3),
	calls_mean: int_at(row, 4),
	calls_max: int_at(row, 5),
	calls_total: int_at(row, 6),
	bytes_mean: int_at(row, 7),
	bytes_max: int_at(row, 8),
	bytes_total: int_at(row, 9),
}

read_allocations! : Gui.SqliteDb => Try(List(TriggerAlloc), Str)
read_allocations! = |database| {
	found = rows!(database, allocations_sql)?
	Ok(found.map(decode_allocation))
}

decode_resources : List(Gui.SqliteValue) -> Resources
decode_resources = |row| {
	run_id: int_at(row, 0),
	phase: text_at(row, 1),
	sample: option_at(row, 2),
	cpu_user: option_at(row, 3),
	cpu_system: option_at(row, 4),
	peak_rss: option_at(row, 5),
	current_rss: option_at(row, 6),
	alloc_calls: option_at(row, 7),
	alloc_bytes: option_at(row, 8),
	dealloc_calls: option_at(row, 9),
	realloc_calls: option_at(row, 10),
	realloc_bytes: option_at(row, 11),
}

read_resources! : Gui.SqliteDb => Try(List(Resources), Str)
read_resources! = |database| {
	found = rows!(database, resources_sql)?
	Ok(found.map(decode_resources))
}

read_metadata! : Gui.SqliteDb => Try(List(Entry), Str)
read_metadata! = |database| {
	found = rows!(database, metadata_sql)?
	Ok(found.map(|row| { key: text_at(row, 0), value: text_at(row, 1) }))
}

read_trust! : Gui.SqliteDb, List(Entry) => Try(Trust, Str)
read_trust! = |database, entries| {
	found = rows!(database, trust_sql)?
	base = { final_state: lookup(entries, "final_state"), clean_shutdown: lookup(entries, "clean_shutdown"), gaps: 0, unfinalized: 0, partial: "", health: None }
	match found.first() {
		Ok(row) => Ok({
			..base,
			gaps: int_at(row, 0),
			unfinalized: int_at(row, 1),
			partial: text_at(row, 2),
			health: Some({ writer_failed: int_at(row, 3), output_limited: int_at(row, 4), omitted: int_at(row, 5) }),
		})
		Err(_) => {
			counts = rows!(database, "SELECT (SELECT count(*) FROM recording_gaps), (SELECT count(*) FROM measurement_status WHERE status = 'unfinalized'), (SELECT coalesce(group_concat(name, ', '), '') FROM measurement_status WHERE status = 'partial')")?
			match counts.first() {
				Ok(row) => Ok({ ..base, gaps: int_at(row, 0), unfinalized: int_at(row, 1), partial: text_at(row, 2) })
				Err(_) => Ok(base)
			}
		}
	}
}

summarize! : Gui.FilesDirRead, Str => Listing
summarize! = |directory, name| {
	blank = { name, capture_id: "", application: "", spec: "", backend: "", scale: "", detail: "", verdict: Unsupported("unreadable") }
	match Gui.Sqlite.open_read!(directory, name) {
		Err(error) => { ..blank, verdict: Unsupported("not a readable database: ${Gui.Sqlite.detail(error)}") }
		Ok(database) => match read_metadata!(database) {
			Err(detail) => { ..blank, verdict: Unsupported("not a capture: ${detail}") }
			Ok(entries) => {
				listed = {
					..blank,
					capture_id: lookup(entries, "capture_id"),
					application: lookup(entries, "app_name"),
					spec: lookup(entries, "spec_name"),
					backend: lookup(entries, "backend"),
					scale: lookup(entries, "benchmark_scale"),
					detail: lookup(entries, "effective_detail"),
				}
				match schema_gate(lookup(entries, "schema_version")) {
					Err(reason) => { ..listed, verdict: Unsupported(reason) }
					Ok({}) => match read_trust!(database, entries) {
						Ok(trust) => { ..listed, verdict: judge(trust) }
						Err(detail) => { ..listed, verdict: Unsupported("unreadable health: ${detail}") }
					}
				}
			}
		}
	}
}

read_families! : Gui.SqliteDb => Try(List(Family), Str)
read_families! = |database| {
	found = rows!(database, families_sql)?
	Ok(found.map(|row| { name: text_at(row, 0), detail: text_at(row, 1), status: text_at(row, 2), reason: text_at(row, 3), rows: int_at(row, 4), omitted: int_at(row, 5) }))
}

read_gaps! : Gui.SqliteDb => Try(List(Gap), Str)
read_gaps! = |database| {
	found = rows!(database, gaps_sql)?
	Ok(found.map(|row| { family: text_at(row, 0), lost: int_at(row, 1), reason: text_at(row, 2) }))
}

read_health! : Gui.SqliteDb => Try([None, Some(Health)], Str)
read_health! = |database| {
	found = rows!(database, health_sql)?
	Ok(
		match found.first() {
			Ok(row) => Some({
				transactions: int_at(row, 0),
				queue_high_water: int_at(row, 1),
				output_bytes: int_at(row, 2),
				omitted_events: int_at(row, 3),
				rows_written: int_at(row, 4),
				writer_failed: int_at(row, 5),
				output_limited: int_at(row, 6),
				drain_ns: int_at(row, 7),
			})
			Err(_) => None
		},
	)
}

read_runs! : Gui.SqliteDb => Try(List(Run), Str)
read_runs! = |database| {
	found = rows!(database, runs_sql)?
	Ok(found.map(|row| { id: int_at(row, 0), phase: text_at(row, 1), sample: option_at(row, 2), outcome: text_at(row, 3), diagnostic: text_at(row, 4), steps: int_at(row, 5), failed: int_at(row, 6) }))
}

run_steps! : Gui.SqliteDb, I64, U64 => Try(List(Step), Str)
run_steps! = |database, run_id, from| {
	page = database.page!({ sql: steps_sql, params: [Integer(run_id), Integer(from.to_i64_wrap())], rows: page_rows }) ? |error| Gui.Sqlite.detail(error)
	Ok(decode_steps(page.rows))
}

decode_steps : List(List(Gui.SqliteValue)) -> List(Step)
decode_steps = |found| found.map(
			|row| {
				run_id: int_at(row, 0),
				ordinal: int_at(row, 1),
				line: int_at(row, 2),
				kind: text_at(row, 3),
				role: text_at(row, 4),
				status: text_at(row, 5),
				duration: option_at(row, 6),
				expected_count: option_at(row, 7),
				observed_count: option_at(row, 8),
				expected_patch: text_at(row, 9),
				observed_patch: text_at(row, 10),
				diagnostic: text_at(row, 11),
			},
		)

read_triggers! : Gui.SqliteDb => Try(List(Trigger), Str)
read_triggers! = |database| {
	found = rows!(database, triggers_sql)?
	Ok(found.map(|row| { phase: text_at(row, 0), trigger: text_at(row, 1), patch_kind: text_at(row, 2), count: int_at(row, 3), min: int_at(row, 4), median: int_at(row, 5), max: int_at(row, 6), iqr: int_at(row, 7) }))
}

read_medians! : Gui.SqliteDb => Try(List(PhaseMedian), Str)
read_medians! = |database| {
	found = rows!(database, medians_sql)?
	Ok(found.map(|row| { phase: text_at(row, 0), count: int_at(row, 1), median: int_at(row, 2) }))
}

read_skips! : Gui.SqliteDb => Try(List(SkipRate), Str)
read_skips! = |database| {
	found = rows!(database, skips_sql)?
	Ok(found.map(|row| { phase: text_at(row, 0), skipped: int_at(row, 1), compared: int_at(row, 2) }))
}

read_frames! : Gui.SqliteDb => Try(Frames, Str)
read_frames! = |database| {
	found = rows!(database, frames_sql)?
	Ok(
		match found.first() {
			Ok(row) => { drawn: int_at(row, 0), over_budget: int_at(row, 1) }
			Err(_) => { drawn: 0, over_budget: 0 }
		},
	)
}

read_budgets! : Gui.SqliteDb => Try(List(Budget), Str)
read_budgets! = |database| {
	found = rows!(database, budgets_sql)?
	Ok(
		match found.first() {
			Ok(row) => budget_rates.map_with_index(|hz, index| { hz, over: int_at(row, index) })
			Err(_) => budget_rates.map(|hz| { hz, over: 0 })
		},
	)
}

decode_bar : List(Gui.SqliteValue) -> Bar
decode_bar = |row| { column: int_at(row, 0), frames: int_at(row, 1), id: int_at(row, 3), run_id: int_at(row, 4), ordinal: int_at(row, 5), layout: int_at(row, 6), prepaint: int_at(row, 7), paint: int_at(row, 8) }

strip! : Gui.SqliteDb, I64, I64 => Try(Strip, Str)
strip! = |database, start, span| {
	counted = rows!(database, frame_count_sql)?
	total = match counted.first() {
		Ok(row) => int_at(row, 0)
		Err(_) => 0
	}
	shown = if span <= 0 or start + span > total total - start else span
	if shown <= 0 {
		Ok({ start, span: 0, total, bars: [] })
	} else {
		result = database.query_with!(strip_sql, [Integer(start), Integer(shown), Integer(columns)]) ? |error| Gui.Sqlite.detail(error)
		Ok({ start, span: shown, total, bars: result.rows.map(decode_bar) })
	}
}

frame! : Gui.SqliteDb, Bar => Try(FrameDetail, Str)
frame! = |database, bar| {
	native = bound_rows!(database, frame_native_sql, bar.id)?
	work = bound_rows!(database, frame_work_sql, bar.id)?
	causes = bound_rows!(database, frame_causes_sql, bar.id)?
	Ok({
		id: bar.id,
		run_id: bar.run_id,
		ordinal: bar.ordinal,
		layout: bar.layout,
		prepaint: bar.prepaint,
		paint: bar.paint,
		native: native.map(|row| { metric: int_at(row, 0), kind: int_at(row, 1), count: int_at(row, 2) }),
		work: work.map(|row| { metric: int_at(row, 0), count: int_at(row, 1) }),
		causes: causes.map(decode_cycle),
	})
}

read_native! : Gui.SqliteDb => Try(List(NativeTotal), Str)
read_native! = |database| {
	found = rows!(database, native_sql)?
	Ok(found.map(|row| { metric: int_at(row, 0), kind: int_at(row, 1), total: int_at(row, 2), max: int_at(row, 3) }))
}

read_work! : Gui.SqliteDb => Try(List(WorkTotal), Str)
read_work! = |database| {
	found = rows!(database, work_totals_sql)?
	Ok(found.map(|row| { metric: int_at(row, 0), total: int_at(row, 1), max: int_at(row, 2) }))
}

read_lists! : Gui.SqliteDb => Try(List(ListRow), Str)
read_lists! = |database| {
	found = rows!(database, lists_sql)?
	Ok(found.map(|row| { list_id: int_at(row, 0), passes: int_at(row, 1), visible: int_at(row, 2), materialized: int_at(row, 3), recycled: int_at(row, 4), live: int_at(row, 5), most: int_at(row, 6) }))
}

read_passes! : Gui.SqliteDb => Try(List(Pass), Str)
read_passes! = |database| {
	found = rows!(database, passes_sql)?
	Ok(found.map(|row| { column: int_at(row, 0), materialized: int_at(row, 1), list_id: int_at(row, 2), visible: int_at(row, 3) }))
}

read_buckets! : Gui.SqliteDb => Try(List(Bucket), Str)
read_buckets! = |database| {
	found = rows!(database, buckets_sql)?
	Ok(found.map(|row| { phase: text_at(row, 0), trigger: text_at(row, 1), patch_kind: text_at(row, 2), bucket: int_at(row, 3), count: int_at(row, 4) }))
}

open! : Gui.FilesDirRead, Str => Try(Opened, Str)
open! = |directory, name| {
	database = Gui.Sqlite.open_read!(directory, name) ? |error| "Could not open ${name}: ${Gui.Sqlite.detail(error)}"
	read!(database, name)
}

open_file! : Gui.FilesFileRead, Str => Try(Opened, Str)
open_file! = |file, name| {
	database = Gui.Sqlite.open_file_read!(file) ? |error| "Could not open ${name}: ${Gui.Sqlite.detail(error)}"
	read!(database, name)
}

progress_sql = "SELECT coalesce((SELECT max(id) FROM cycles), 0), coalesce((SELECT max(id) FROM gpui_frames), 0), coalesce((SELECT max(id) FROM steps), 0), (SELECT count(*) FROM runs WHERE ended_ns IS NOT NULL), coalesce((SELECT value FROM metadata WHERE key = 'final_state'), ''), coalesce((SELECT value FROM metadata WHERE key = 'capture_id'), '')"

progress! : Gui.SqliteDb => Try(Progress, Str)
progress! = |database| {
	found = rows!(database, progress_sql)?
	match found.first() {
		Ok(row) => Ok({ cycles: int_at(row, 0), frames: int_at(row, 1), steps: int_at(row, 2), ended: int_at(row, 3), final_state: text_at(row, 4), capture_id: text_at(row, 5) })
		Err(_) => Err("This capture's progress could not be read")
	}
}

read! : Gui.SqliteDb, Str => Try(Opened, Str)
read! = |database, name| {
	entries = read_metadata!(database) ? |detail| "${name} is not a capture: ${detail}"
	schema_gate(lookup(entries, "schema_version"))?
	trust = read_trust!(database, entries)?
	families = read_families!(database)?
	gaps = read_gaps!(database)?
	health = read_health!(database)?
	runs = read_runs!(database)?
	triggers = read_triggers!(database)?
	medians = read_medians!(database)?
	skips = read_skips!(database)?
	frames = read_frames!(database)?
	budgets = read_budgets!(database)?
	strip = strip!(database, 0, 0)?
	native = read_native!(database)?
	work = read_work!(database)?
	lists = read_lists!(database)?
	passes = read_passes!(database)?
	buckets = read_buckets!(database)?
	allocations = read_allocations!(database)?
	resources = read_resources!(database)?
	Ok({ revision: 0, name, database, metadata: entries, families, gaps, health, runs, triggers, medians, skips, frames, budgets, strip, native, work, lists, passes, buckets, allocations, resources, verdict: judge(trust) })
}
