## The capture's one clock (US-26, W6): cycles by trigger, drawn frames, and
## virtual-list passes over a span of the process-relative interval every
## owner recorded. A frame's causes and a pass's origin are read only through
## the keys the recorder wrote. Nothing here is inferred from ordering or
## overlap: two marks that touch on the clock are not thereby related.
import pf.Gui
import Capture

## The longest cycle of one trigger that starts in a column, and how many of
## that trigger's cycles start there.
CycleMark : { column : I64, cycles : I64, cycle : Capture.Cycle, start : I64, end : I64 }

## The costliest frame, by its host-owned stages, of those that start in a
## column, and how many cycles its owner recorded it was the first to draw.
FrameMark : { column : I64, frames : I64, bar : Capture.Bar, start : I64, end : I64, causes : I64 }

## The list pass of a column that materialised the most, and what produced it:
## the frame whose paint settled it or the cycle whose patch performed it, as
## recorded; `None` is a link the recorder did not make.
PassMark : {
	column : I64,
	passes : I64,
	list_id : I64,
	origin : Str,
	frame : [None, Some(I64)],
	cycle : [None, Some(I64)],
	visible : I64,
	materialized : I64,
	start : I64,
	end : I64,
}

## `span` nanoseconds of the clock from `start`, within the capture's own
## `first` to `last`. `triggers` are every trigger of the capture, so a lane
## keeps its place as the window moves.
Window : {
	first : I64,
	last : I64,
	start : I64,
	span : I64,
	triggers : List(Str),
	cycles : List(CycleMark),
	frames : List(FrameMark),
	passes : List(PassMark),
}

Timeline := [].{
	CycleMark : CycleMark
	FrameMark : FrameMark
	PassMark : PassMark
	Window : Window

	## How many columns a lane is divided into.
	columns : I64
	columns = columns

	## The shortest span a window may be zoomed to.
	shortest : I64
	shortest = 100000

	empty : Window
	empty = { first: 0, last: 0, start: 0, span: 0, triggers: [], cycles: [], frames: [], passes: [] }

	## The marks of `span` nanoseconds from `start`; a `span` of zero or less is
	## the whole capture.
	read! : Gui.SqliteDb, I64, I64 => Try(Window, Str)
	read! = read!

	## The window a wheel asks for: the vertical wheel halves or doubles the
	## span around the instant under the pointer at `offset` of `width`
	## pixels, and the horizontal wheel pans by an eighth.
	zoomed : Window, I64, I64, I32, I32 -> [None, Some({ start : I64, span : I64 })]
	zoomed = zoomed
}

columns : I64
columns = 360

int_at : List(Gui.SqliteValue), U64 -> I64
int_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => value
	_ => 0
}

option_at : List(Gui.SqliteValue), U64 -> [None, Some(I64)]
option_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => Some(value)
	_ => None
}

text_at : List(Gui.SqliteValue), U64 -> Str
text_at = |row, index| match row.get(index) {
	Ok(String(value)) => value
	_ => ""
}

query! : Gui.SqliteDb, Str, List(Gui.SqliteValue) => Try(List(List(Gui.SqliteValue)), Str)
query! = |database, sql, values| match database.query_with!(sql, values) {
	Ok(result) => Ok(result.rows)
	Err(error) => Err(Gui.Sqlite.detail(error))
}

extent_sql = "SELECT min(s), max(e) FROM (SELECT min(start_ns) AS s, max(end_ns) AS e FROM cycles UNION ALL SELECT min(start_ns), max(end_ns) FROM gpui_frames UNION ALL SELECT min(start_ns), max(end_ns) FROM virtual_list_frames)"

triggers_sql = "SELECT DISTINCT trigger FROM cycles ORDER BY trigger"

## A mark's column is where it starts, or the window's first column for a
## mark that began before the window. With one max() aggregate, SQLite takes
## the bare columns from the row that holds the maximum.
column_expression = "min((max(start_ns, ?1) - ?1) * ?3 / ?2, ?3 - 1)"

within = "end_ns >= ?1 AND start_ns <= ?1 + ?2"

cycles_sql = "WITH c AS (SELECT id, run_id, ordinal, step_ordinal, measurement_phase, trigger, patch_kind, duration_ns, roc_callback_ns, validate_ns, apply_ns, start_ns, end_ns, target_kind, target_identity, ${column_expression} AS col FROM cycles WHERE ${within}) SELECT col, count(*), max(end_ns - start_ns), id, run_id, ordinal, step_ordinal, measurement_phase, trigger, patch_kind, duration_ns, roc_callback_ns, validate_ns, apply_ns, start_ns, end_ns, target_kind, target_identity FROM c GROUP BY trigger, col ORDER BY trigger, col"

frames_sql = "WITH f AS (SELECT id, run_id, ordinal, layout_request_ns AS l, prepaint_ns AS p, paint_ns AS q, start_ns, end_ns, (SELECT count(*) FROM gpui_frame_cycles k WHERE k.frame_id = gpui_frames.id) AS n, ${column_expression} AS col FROM gpui_frames WHERE ${within}) SELECT col, count(*), max(l + p + q), id, run_id, ordinal, l, p, q, start_ns, end_ns, n FROM f GROUP BY col ORDER BY col"

passes_sql = "WITH v AS (SELECT list_id, origin, (SELECT ordinal FROM gpui_frames g WHERE g.id = virtual_list_frames.frame_id) AS frame, (SELECT ordinal FROM cycles c WHERE c.id = virtual_list_frames.cycle_id) AS cycle, visible_items, materialized_entities, start_ns, end_ns, ${column_expression} AS col FROM virtual_list_frames WHERE ${within}) SELECT col, count(*), max(materialized_entities), list_id, origin, frame, cycle, visible_items, start_ns, end_ns FROM v GROUP BY col ORDER BY col"

decode_cycle : List(Gui.SqliteValue) -> CycleMark
decode_cycle = |row| {
	column: int_at(row, 0),
	cycles: int_at(row, 1),
	cycle: {
		id: int_at(row, 3),
		run_id: int_at(row, 4),
		ordinal: int_at(row, 5),
		step_ordinal: option_at(row, 6),
		phase: text_at(row, 7),
		trigger: text_at(row, 8),
		patch_kind: text_at(row, 9),
		duration: int_at(row, 10),
		callback: int_at(row, 11),
		validate: int_at(row, 12),
		apply: int_at(row, 13),
		target: Capture.target_at(row, 16),
	},
	start: int_at(row, 14),
	end: int_at(row, 15),
}

decode_frame : List(Gui.SqliteValue) -> FrameMark
decode_frame = |row| {
	column: int_at(row, 0),
	frames: int_at(row, 1),
	bar: { column: int_at(row, 0), frames: int_at(row, 1), id: int_at(row, 3), run_id: int_at(row, 4), ordinal: int_at(row, 5), layout: int_at(row, 6), prepaint: int_at(row, 7), paint: int_at(row, 8) },
	start: int_at(row, 9),
	end: int_at(row, 10),
	causes: int_at(row, 11),
}

decode_pass : List(Gui.SqliteValue) -> PassMark
decode_pass = |row| {
	column: int_at(row, 0),
	passes: int_at(row, 1),
	materialized: int_at(row, 2),
	list_id: int_at(row, 3),
	origin: text_at(row, 4),
	frame: option_at(row, 5),
	cycle: option_at(row, 6),
	visible: int_at(row, 7),
	start: int_at(row, 8),
	end: int_at(row, 9),
}

read! : Gui.SqliteDb, I64, I64 => Try(Window, Str)
read! = |database, start, span| {
	extent = query!(database, extent_sql, [])?
	bounds = match extent.first() {
		Ok(row) => match (option_at(row, 0), option_at(row, 1)) {
			(Some(first), Some(last)) => Some({ first, last })
			_ => None
		}
		Err(_) => None
	}
	match bounds {
		None => Ok(Timeline.empty)
		Some({ first, last }) => {
			whole = if last - first < 1 1 else last - first
			shown = if span <= 0 or span > whole whole else span
			from = if span <= 0 or start < first first else if start + shown > first + whole first + whole - shown else start
			window = [Integer(from), Integer(shown), Integer(columns)]
			triggers = query!(database, triggers_sql, [])?
			cycles = query!(database, cycles_sql, window)?
			frames = query!(database, frames_sql, window)?
			passes = query!(database, passes_sql, window)?
			Ok({
				first,
				last: first + whole,
				start: from,
				span: shown,
				triggers: triggers.map(|row| text_at(row, 0)),
				cycles: cycles.map(decode_cycle),
				frames: frames.map(decode_frame),
				passes: passes.map(decode_pass),
			})
		}
	}
}

zoomed : Window, I64, I64, I32, I32 -> [None, Some({ start : I64, span : I64 })]
zoomed = |window, offset, width, dx, dy| {
	whole = window.last - window.first
	if whole <= 0 or width <= 0 or window.span <= 0 {
		None
	} else {
		at = if offset < 0 0 else if offset > width width else offset
		anchor = window.start + at * window.span / width
		smallest = if whole < Timeline.shortest whole else Timeline.shortest
		requested = if dy < 0 window.span / 2 else if dy > 0 window.span * 2 else window.span
		span = if requested < smallest smallest else if requested > whole whole else requested
		panned = if dx > 0 span / 8 else if dx < 0 -(span / 8) else 0
		unclamped = anchor - at * span / width + panned
		start = if unclamped < window.first window.first else if unclamped > window.last - span window.last - span else unclamped
		if start == window.start and span == window.span None else Some({ start, span })
	}
}

sample : Window
sample = { ..Timeline.empty, first: 0, last: 1000000, start: 0, span: 1000000 }

expect zoomed(sample, 360, 720, 0, -1) == Some({ start: 250000, span: 500000 })
expect zoomed(sample, 0, 720, 0, 1) == None
expect zoomed({ ..sample, span: 500000 }, 0, 720, 1, 0) == Some({ start: 62500, span: 500000 })
