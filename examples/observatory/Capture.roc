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
## any of their tables are read.
Verdict : [Complete, Partial(Str), Untrusted(Str), Unsupported(Str)]

## What the capture list shows for one file.
Listing : { name : Str, application : Str, spec : Str, backend : Str, scale : Str, detail : Str, verdict : Verdict }

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
}

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

## A capture that passed the schema gate. Everything but the steps is read
## when it opens; steps are read one run at a time through the held connection.
Opened : {
	name : Str,
	database : Gui.SqliteDb,
	metadata : List(Entry),
	families : List(Family),
	gaps : List(Gap),
	health : [None, Some(Health)],
	runs : List(Run),
	steps : List(Step),
	steps_more : Bool,
	triggers : List(Trigger),
	medians : List(PhaseMedian),
	skips : List(SkipRate),
	frames : Frames,
	cycles : List(Cycle),
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
	Trust : Trust
	Verdict : Verdict
	Listing : Listing
	Opened : Opened
	Cycle : Cycle
	Span : Span
	Work : Work
	Counter : Counter
	Inspected : Inspected
	Decomposition : Decomposition
	TriggerAlloc : TriggerAlloc
	Resources : Resources

	## The one schema this application reads.
	supported_schema : Str
	supported_schema = "19"

	## Read enough of one file to list it: identity and a verdict.
	summarize! : Gui.FilesDirRead, Str => Listing
	summarize! = summarize!

	## Open one capture, refuse it unless it is schema 19, and read every table
	## the views present.
	open! : Gui.FilesDirRead, Str => Try(Opened, Str)
	open! = open!

	## The steps of one run, at most `step_page` of them; `more` says the run
	## continues past the page.
	run_steps! : Gui.SqliteDb, I64 => Try({ steps : List(Step), more : Bool }, Str)
	run_steps! = run_steps!

	step_page : U64
	step_page = step_page

	## How many of the slowest cycles of each phase, trigger, and patch kind are
	## read when a capture opens.
	cycle_page : I64
	cycle_page = cycle_page

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
	rule = "Untrusted when the capture is not finalised, shut down uncleanly, lost events, hit its output limit, had a writer failure, or recorded a gap. Partial when any measurement family is partial. Otherwise complete: not_recorded and unavailable families are declared absences, not losses."

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
	}

	verdict_reason : Verdict -> Str
	verdict_reason = |verdict| match verdict {
		Complete => "every family finalised without recorded loss"
		Partial(reason) => reason
		Untrusted(reason) => reason
		Unsupported(reason) => reason
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
	cycle: { id: 1, run_id: 1, ordinal: 0, step_ordinal: None, phase: "interactive", trigger: "init", patch_kind: "mount", duration: 47776342, callback: 521128, validate: 17894, apply: 39546 },
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
schema_gate = |version| if version == "19" {
	Ok({})
} else if Str.is_empty(version) {
	Err("This file records no schema version; Observatory reads schema 19")
} else {
	Err("Schema ${version} is not supported; Observatory reads schema 19")
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

judge : Trust -> Verdict
judge = |trust| {
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
expect judge({ final_state: "recording", clean_shutdown: "0", gaps: 0, unfinalized: 0, partial: "", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Untrusted("not finalised (recording); unclean shutdown")
expect judge({ final_state: "complete", clean_shutdown: "1", gaps: 0, unfinalized: 0, partial: "timing_environment", health: Some({ writer_failed: 0, output_limited: 0, omitted: 0 }) }) == Partial("partial families: timing_environment")
expect schema_gate("4") == Err("Schema 4 is not supported; Observatory reads schema 19")

## Cells. Every column read through these is declared by schema 19; a nullable
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

steps_sql = "SELECT run_id, ordinal, source_line, kind, role, status, duration_ns, expected_count, observed_count, coalesce(expected_patch_kind, ''), coalesce(observed_patch_kind, ''), coalesce(diagnostic, '') FROM steps WHERE run_id = ? ORDER BY ordinal"

step_page : U64
step_page = 10000

## Warmup runs exist to be discarded, so every cycle statistic excludes them.
## Median by averaging the one or two middle ranks; interquartile range by
## nearest rank. Both are computed over every remaining cycle of the group.
triggers_sql = "WITH c AS (SELECT measurement_phase AS phase, trigger, patch_kind, duration_ns AS d, row_number() OVER (PARTITION BY measurement_phase, trigger, patch_kind ORDER BY duration_ns) AS rn, count(*) OVER (PARTITION BY measurement_phase, trigger, patch_kind) AS n FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')) SELECT phase, trigger, patch_kind, n, min(d), CAST(round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN d END)) AS INTEGER) AS median, max(d), max(CASE WHEN rn = (3 * n + 3) / 4 THEN d END) - max(CASE WHEN rn = (n + 3) / 4 THEN d END) FROM c GROUP BY phase, trigger, patch_kind ORDER BY phase, median DESC, trigger, patch_kind"

medians_sql = "WITH c AS (SELECT measurement_phase AS phase, duration_ns AS d, row_number() OVER (PARTITION BY measurement_phase ORDER BY duration_ns) AS rn, count(*) OVER (PARTITION BY measurement_phase) AS n FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')) SELECT phase, n, CAST(round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN d END)) AS INTEGER) FROM c GROUP BY phase ORDER BY phase"

## An absent kind is zero only for a cycle whose component work was recorded,
## so only those cycles are summed.
skips_sql = "SELECT c.measurement_phase, coalesce(sum(CASE w.kind WHEN 2 THEN w.count END), 0), coalesce(sum(CASE w.kind WHEN 1 THEN w.count END), 0) FROM cycles c LEFT JOIN component_work_counts w ON w.cycle_id = c.id WHERE c.component_work_recorded = 1 AND c.run_id IN (SELECT id FROM runs WHERE phase <> 'warmup') GROUP BY c.measurement_phase ORDER BY c.measurement_phase"

frames_sql = "SELECT count(*), coalesce(sum(CASE WHEN layout_request_ns + prepaint_ns + paint_ns > 16666667 THEN 1 ELSE 0 END), 0) FROM gpui_frames"

cycle_page : I64
cycle_page = 1000

## Warmups are excluded, as in every cycle statistic.
cycles_sql = "SELECT id, run_id, ordinal, step_ordinal, phase, trigger, patch_kind, d, callback, validate, apply FROM (SELECT id, run_id, ordinal, step_ordinal, measurement_phase AS phase, trigger, patch_kind, duration_ns AS d, roc_callback_ns AS callback, validate_ns AS validate, apply_ns AS apply, row_number() OVER (PARTITION BY measurement_phase, trigger, patch_kind ORDER BY duration_ns DESC, id) AS rank FROM cycles WHERE run_id IN (SELECT id FROM runs WHERE phase <> 'warmup')) WHERE rank <= ? ORDER BY phase, d DESC, id"

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

read_cycles! : Gui.SqliteDb => Try(List(Cycle), Str)
read_cycles! = |database| {
	found = bound_rows!(database, cycles_sql, cycle_page)?
	Ok(found.map(decode_cycle))
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
}

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
	blank = { name, application: "", spec: "", backend: "", scale: "", detail: "", verdict: Unsupported("unreadable") }
	match Gui.Sqlite.open_read!(directory, name) {
		Err(error) => { ..blank, verdict: Unsupported("not a readable database: ${Gui.Sqlite.detail(error)}") }
		Ok(database) => match read_metadata!(database) {
			Err(detail) => { ..blank, verdict: Unsupported("not a capture: ${detail}") }
			Ok(entries) => {
				listed = {
					..blank,
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

run_steps! : Gui.SqliteDb, I64 => Try({ steps : List(Step), more : Bool }, Str)
run_steps! = |database, run_id| {
	page = database.page!({ sql: steps_sql, params: [Integer(run_id)], rows: step_page }) ? |error| Gui.Sqlite.detail(error)
	Ok({ steps: decode_steps(page.rows), more: page.more })
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

open! : Gui.FilesDirRead, Str => Try(Opened, Str)
open! = |directory, name| {
	database = Gui.Sqlite.open_read!(directory, name) ? |error| "Could not open ${name}: ${Gui.Sqlite.detail(error)}"
	entries = read_metadata!(database) ? |detail| "${name} is not a capture: ${detail}"
	schema_gate(lookup(entries, "schema_version"))?
	trust = read_trust!(database, entries)?
	families = read_families!(database)?
	gaps = read_gaps!(database)?
	health = read_health!(database)?
	runs = read_runs!(database)?
	first = match runs.first() {
		Ok(run) => run_steps!(database, run.id)?
		Err(_) => { steps: [], more: False }
	}
	triggers = read_triggers!(database)?
	medians = read_medians!(database)?
	skips = read_skips!(database)?
	frames = read_frames!(database)?
	cycles = read_cycles!(database)?
	allocations = read_allocations!(database)?
	resources = read_resources!(database)?
	Ok({ name, database, metadata: entries, families, gaps, health, runs, steps: first.steps, steps_more: first.more, triggers, medians, skips, frames, cycles, allocations, resources, verdict: judge(trust) })
}
