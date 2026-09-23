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
	Ok({ name, database, metadata: entries, families, gaps, health, runs, steps: first.steps, steps_more: first.more, triggers, medians, skips, frames, verdict: judge(trust) })
}
