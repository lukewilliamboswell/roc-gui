## The specification source beside its results (US-19 to US-21). A person
## grants a folder of specification sources; the capture names its
## specification only by `spec_name` and `spec_hash`, never by path, so the
## file is found by hashing each `.scm` file of the folder and comparing with
## `spec_hash`. Only a file whose bytes hash to it is the source that ran, and
## only then are results placed on its lines. A file that declares the same
## test but hashes differently has changed since the capture.
import pf.Gui
import Capture

## What the granted folder holds for the open capture. `Unchecked` is before
## any folder is granted; `Unnamed` is a capture that ran no specification.
Found : [
	Unchecked,
	Unnamed,
	Missing({ folder : Str, files : U64 }),
	Matched({ folder : Str, file : Str, lines : List(Str) }),
	Changed({ folder : Str, file : Str }),
]

## One sample's values for a step, for the inspector.
Sample : { run : I64, index : I64, status : Str, duration : [None, Some(I64)], cycles : I64 }

## One expected-versus-observed value of an assertion vector.
Assertion : { group : Str, name : Str, expected : [None, Some(I64)], observed : [None, Some(I64)] }

## A step's evidence on its line: the selected run's, or for the median the
## median across the samples, with every sample's own values kept.
Mark : {
	ordinal : I64,
	line : I64,
	kind : Str,
	role : Str,
	status : Str,
	duration : [None, Some(I64)],
	cycles : I64,
	patch : Str,
	expected_count : [None, Some(I64)],
	observed_count : [None, Some(I64)],
	expected_patch : Str,
	observed_patch : Str,
	diagnostic : Str,
	samples : List(Sample),
	assertions : List(Assertion),
}

## Which runs the gutter shows: one run, or the median across the samples.
Mode : [OneRun(I64), Median]

## The marks of one mode, the rows they lay the source out in, the ordinal of
## the benchmark's mark if it has one, and the request that read them.
Annotation : { mode : Mode, marks : List(Mark), rows : List(Row), boundary : [None, Some(I64)], read : U64 }

## The folder of specification sources a person granted, what it holds for
## the capture of revision `of`, the annotation on screen, the line chosen in
## it, and where its list was last brought to.
Shown : {
	folder : [None, Some({ name : Str, directory : Gui.Files.Dir.Read })],
	of : U64,
	found : Found,
	annotation : [None, Some(Annotation)],
	chosen : [None, Some(U64)],
	scroll : [None, Some(Gui.ScrollRequest)],
	reading : [None, Some(U64)],
}

## One row of the annotated source: a line and the steps that ran from it, and
## below a failing step its hint and the heading and rows of its assertion
## table. Lines count from one; marks and assertions are indices.
Row : [Line(U64, List(U64)), Hint(U64), AssertHead(U64), Assert(U64, U64)]

SpecSource := [].{
	Found : Found
	Sample : Sample
	Assertion : Assertion
	Mark : Mark
	Mode : Mode
	Annotation : Annotation
	Row : Row
	Shown : Shown

	## No folder granted.
	none : Shown
	none = { folder: None, of: 0, found: Unchecked, annotation: None, chosen: None, scroll: None, reading: None }

	## An annotation of marks read by one request.
	annotation : List(Str), Mode, List(Mark), U64 -> Annotation
	annotation = |lines, mode, marks, read| {
		boundary = match marks.find_first(|mark| mark.role == "boundary") {
			Ok(mark) => Some(mark.ordinal)
			Err(_) => None
		}
		{ mode, marks, rows: layout(lines, marks), boundary, read }
	}

	## The row a step's line is on, if the source has that line.
	row_of : Annotation, I64 -> [None, Some(U64)]
	row_of = |shown, ordinal| match shown.rows.find_first_index(
		|row| match row {
			Line(_, found) => found.any(|at| (shown.marks.get(at) ?? empty_mark).ordinal == ordinal)
			_ => False
		},
	) {
		Ok(index) => Some(index)
		Err(_) => None
	}

	## Find the capture's specification in a granted folder of sources.
	find! : Gui.Files.Dir.Read, Str, Capture.Opened => Try(Found, Str)
	find! = find!

	## Read the steps, cycles, and assertions of the runs a mode shows.
	annotate! : Gui.Sqlite.Db, Capture.Opened, Mode => Try(List(Mark), Str)
	annotate! = annotate!

	## The sample runs of a capture, which the median is taken across.
	samples : Capture.Opened -> List(Capture.Run)
	samples = |opened| opened.runs.keep_if(|run| run.phase == "sample")

	## The rows of the annotated source: every line, and below a failing
	## step's line its diagnostic and its assertion tables.
	layout : List(Str), List(Mark) -> List(Row)
	layout = layout

	## Why a step's cycle count is absent: its family is not complete, or its
	## cycles ran before the benchmark's mark, which a summary capture does not
	## record.
	cycles_absence : Capture.Opened, [None, Some(I64)], Mark -> [Recorded, Absent(Str)]
	cycles_absence = cycles_absence

	## One source line split into styled runs: comments, strings, keywords,
	## the operator after an opening parenthesis, and parentheses.
	tokens : Str -> List({ text : Str, class : [Plain, Paren, Head, Keyword, Literal, Comment] })
	tokens = tokens

	## The median of a list of values: the middle one, or the mean of the two
	## middle ones.
	median : List(I64) -> [None, Some(I64)]
	median = median
}

## Hashes are compared in the recorder's own spelling.
recorded_hash : Str -> Str
recorded_hash = |digest| "sha256:${digest}"

is_source : Gui.Files.Entry -> Bool
is_source = |entry| entry.kind == File and Str.ends_with(entry.name, ".scm")

## The file hashing to `spec_hash` is the specification that ran. Failing
## that, a file declaring the capture's test has changed since the capture.
find! : Gui.Files.Dir.Read, Str, Capture.Opened => Try(Found, Str)
find! = |directory, folder, opened| {
	hash = Capture.metadata(opened, "spec_hash")
	name = Capture.metadata(opened, "spec_name")
	if Str.is_empty(hash) or Str.is_empty(name) {
		Ok(Unnamed)
	} else {
		entries = directory.list!() ? |_| "The folder of specification sources could not be listed."
		sources = entries.keep_if(is_source).map(|entry| entry.name)
		var $matched = None
		for file in sources {
			if $matched == None {
				match directory.sha256!(file) {
					Ok(digest) => if recorded_hash(digest) == hash {
						$matched = Some(file)
					}
					Err(_) => {}
				}
			}
		}
		match $matched {
			Some(file) => {
				bytes = directory.read!(file) ? |_| "${file} could not be read."
				text = Str.from_utf8(bytes) ? |_| "${file} is not UTF-8."
				lines = source_lines(text)
				Ok(Matched({ folder, file, lines }))
			}
			None => {
				declared = "(test \"${name}\""
				var $changed = None
				for file in sources {
					if $changed == None {
						match directory.read!(file) {
							Ok(bytes) => if Str.contains(Str.from_utf8_lossy(bytes), declared) {
								$changed = Some(file)
							}
							Err(_) => {}
						}
					}
				}
				match $changed {
					Some(file) => Ok(Changed({ folder, file }))
					None => Ok(Missing({ folder, files: sources.len() }))
				}
			}
		}
	}
}

## A file's lines, without the empty one after its last line break.
source_lines : Str -> List(Str)
source_lines = |text| {
	lines = Str.split_on(text, "\n")
	match lines.last() {
		Ok(last) if Str.is_empty(last) => lines.drop_last(1)
		_ => lines
	}
}

expect source_lines("(test\n  (steps))\n") == ["(test", "  (steps))"]
expect source_lines("one") == ["one"]

## Rows of one long table are read in pages keyed by ordinal, so a run of any
## length is read whole without one result exceeding the host's row bound.
chunk : U64
chunk = 5000

all_rows! : Gui.Sqlite.Db, Str, I64 => Try(List(List(Gui.Sqlite.Value)), Str)
all_rows! = |database, sql, run_id| rows_from!(database, sql, run_id, 0, [])

rows_from! : Gui.Sqlite.Db, Str, I64, I64, List(List(Gui.Sqlite.Value)) => Try(List(List(Gui.Sqlite.Value)), Str)
rows_from! = |database, sql, run_id, from, held| {
	page = database.page!({ sql, params: [Integer(run_id), Integer(from)], rows: chunk }) ? |error| Gui.Sqlite.detail(error)
	rows = held.concat(page.rows)
	match page.rows.last() {
		Ok(row) if page.more => rows_from!(database, sql, run_id, int_at(row, 0) + 1, rows)
		_ => Ok(rows)
	}
}

steps_sql = "SELECT ordinal, source_line, kind, role, status, duration_ns, expected_count, observed_count, coalesce(expected_patch_kind, ''), coalesce(observed_patch_kind, ''), coalesce(diagnostic, '') FROM steps WHERE run_id = ? AND ordinal >= ? ORDER BY ordinal"

cycles_sql = "SELECT step_ordinal, count(*), group_concat(DISTINCT patch_kind) FROM cycles WHERE run_id = ? AND step_ordinal >= ? GROUP BY step_ordinal ORDER BY step_ordinal"

work_sql = "SELECT s.ordinal, a.kind, a.expected_count, a.observed_count FROM component_work_assertions a JOIN steps s ON s.id = a.step_id WHERE s.run_id = ? AND s.ordinal >= ? ORDER BY s.ordinal, a.kind"

## The counter assertion tables, each a row of expected and observed columns.
counter_tables : List(Str)
counter_tables = ["audio", "clipboard", "database", "http", "tcp"]

counter_sql : Str -> Str
counter_sql = |table| "SELECT s.ordinal, a.* FROM ${table}_counter_assertions a JOIN steps s ON s.id = a.step_id WHERE s.run_id = ? AND s.ordinal >= ? ORDER BY s.ordinal"

text_at : List(Gui.Sqlite.Value), U64 -> Str
text_at = |row, index| match row.get(index) {
	Ok(String(value)) => value
	Ok(Integer(value)) => value.to_str()
	_ => ""
}

option_at : List(Gui.Sqlite.Value), U64 -> [None, Some(I64)]
option_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => Some(value)
	_ => None
}

int_at : List(Gui.Sqlite.Value), U64 -> I64
int_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => value
	_ => 0
}

## One run's steps, cycles, and assertions, each keyed by step ordinal.
Read : { run : Capture.Run, steps : List(List(Gui.Sqlite.Value)), cycles : Dict(I64, { count : I64, patch : Str }), assertions : Dict(I64, List(Assertion)) }

read_run! : Gui.Sqlite.Db, Capture.Run => Try(Read, Str)
read_run! = |database, run| {
	steps = all_rows!(database, steps_sql, run.id)?
	cycle_rows = all_rows!(database, cycles_sql, run.id)?
	cycles = cycle_rows.fold(Dict.empty(), |found, row| found.insert(int_at(row, 0), { count: int_at(row, 1), patch: text_at(row, 2) }))
	work_rows = all_rows!(database, work_sql, run.id)?
	var $assertions = work_rows.fold(
		Dict.empty(),
		|found, row| {
			kind = int_at(row, 1).to_u64_wrap()
			name = Capture.work_kinds.get(kind) ?? kind.to_str()
			add(found, int_at(row, 0), { group: "component work", name, expected: option_at(row, 2), observed: option_at(row, 3) })
		},
	)
	for table in counter_tables {
		result = database.query_with!(counter_sql(table), [Integer(run.id), Integer(0)]) ? |error| Gui.Sqlite.detail(error)
		for row in result.rows {
			$assertions = counter_values(table, result.columns, row).fold($assertions, |found, value| add(found, int_at(row, 0), value))
		}
	}
	Ok({ run, steps, cycles, assertions: $assertions })
}

add : Dict(I64, List(Assertion)), I64, Assertion -> Dict(I64, List(Assertion))
add = |found, ordinal, value| found.insert(ordinal, (found.get(ordinal) ?? []).append(value))

## A counter assertion row's `expected_X` and `observed_X` columns, paired.
counter_values : Str, List(Str), List(Gui.Sqlite.Value) -> List(Assertion)
counter_values = |table, columns, row| {
	var $values = []
	var $index = 0.U64
	for column in columns {
		if Str.starts_with(column, "expected_") {
			name = Str.drop_prefix(column, "expected_")
			observed = match columns.find_first_index(|other| other == "observed_${name}") {
				Ok(at) => option_at(row, at)
				Err(_) => None
			}
			$values = $values.append({ group: "${table} counters", name: Str.replace_each(name, "_", " "), expected: option_at(row, $index), observed })
		}
		$index = $index + 1
	}
	$values
}

## A step as one run recorded it.
mark_of : Read, List(Gui.Sqlite.Value) -> Mark
mark_of = |read, row| {
	ordinal = int_at(row, 0)
	cycles = read.cycles.get(ordinal) ?? { count: 0, patch: "" }
	{
		ordinal,
		line: int_at(row, 1),
		kind: text_at(row, 2),
		role: text_at(row, 3),
		status: text_at(row, 4),
		duration: option_at(row, 5),
		cycles: cycles.count,
		patch: cycles.patch,
		expected_count: option_at(row, 6),
		observed_count: option_at(row, 7),
		expected_patch: text_at(row, 8),
		observed_patch: text_at(row, 9),
		diagnostic: text_at(row, 10),
		samples: [],
		assertions: read.assertions.get(ordinal) ?? [],
	}
}

annotate! : Gui.Sqlite.Db, Capture.Opened, Mode => Try(List(Mark), Str)
annotate! = |database, opened, mode| match mode {
	OneRun(run_id) => match opened.runs.find_first(|run| run.id == run_id) {
		Ok(run) => {
			read = read_run!(database, run)?
			Ok(read.steps.map(|row| mark_of(read, row)))
		}
		Err(_) => Err("Run ${run_id.to_str()} is not in this capture.")
	}
	Median => {
		var $reads = []
		for run in SpecSource.samples(opened) {
			$reads = $reads.append(read_run!(database, run)?)
		}
		match $reads.first() {
			Ok(first) => Ok(first.steps.map(|row| median_mark($reads, mark_of(first, row))))
			Err(_) => Err("This capture has no samples to take a median across.")
		}
	}
}

## One step across the samples: the median duration and cycle count, failed
## when any sample failed it, with the first failing sample's diagnostic and
## assertions, and every sample's own values.
median_mark : List(Read), Mark -> Mark
median_mark = |reads, base| {
	each = reads.map(
		|read| match step_row(read.steps, base.ordinal) {
			Some(row) => Some(mark_of(read, row))
			None => None
		},
	)
	samples = reads.map_with_index(
		|read, index| match each.get(index) {
			Ok(Some(mark)) => [{ run: read.run.id, index: or_else(read.run.sample, index.to_i64_wrap()), status: mark.status, duration: mark.duration, cycles: mark.cycles }]
			_ => []
		},
	)
		.join()
	durations = samples.keep_if(|sample| sample.duration != None).map(|sample| or_else(sample.duration, 0))
	duration = if durations.len() == samples.len() median(durations) else None
	failed = each.keep_if(|mark| match mark {
		Some(found) => found.status == "fail"
		None => False
	})
	shown = match failed.first() {
		Ok(Some(found)) => found
		_ => base
	}
	{ ..shown, duration, cycles: or_else(median(samples.map(|sample| sample.cycles)), 0), samples }
}

## A run's steps are numbered from zero, so a step's ordinal is its row.
step_row : List(List(Gui.Sqlite.Value)), I64 -> [None, Some(List(Gui.Sqlite.Value))]
step_row = |steps, ordinal| match steps.get(ordinal.to_u64_wrap()) {
	Ok(row) if int_at(row, 0) == ordinal => Some(row)
	_ => match steps.find_first(|row| int_at(row, 0) == ordinal) {
		Ok(row) => Some(row)
		Err(_) => None
	}
}

or_else : [None, Some(a)], a -> a
or_else = |value, fallback| match value {
	Some(held) => held
	None => fallback
}

median : List(I64) -> [None, Some(I64)]
median = |values| {
	sorted = values.sort_with(|a, b| if a < b Before else if a > b After else Same)
	count = sorted.len()
	if count == 0 {
		None
	} else if count % 2 == 1 {
		Some(sorted.get(count / 2) ?? 0)
	} else {
		Some(((sorted.get(count / 2 - 1) ?? 0) + (sorted.get(count / 2) ?? 0)) / 2)
	}
}

expect median([5, 1, 3]) == Some(3)
expect median([4, 1, 3, 2]) == Some(2)
expect median([]) == None

cycles_absence : Capture.Opened, [None, Some(I64)], Mark -> [Recorded, Absent(Str)]
cycles_absence = |opened, boundary, mark| {
	before_mark = match boundary {
		Some(ordinal) => mark.ordinal < ordinal
		None => False
	}
	if !Capture.complete(opened, "host_cycles") {
		Absent(Capture.absence(opened, "host_cycles"))
	} else if before_mark and Capture.metadata(opened, "effective_detail") == "summary" {
		Absent("this step ran before the benchmark's mark, and a summary capture does not record setup cycles")
	} else {
		Recorded
	}
}

layout : List(Str), List(Mark) -> List(Row)
layout = |lines, marks| {
	# The steps of each line, gathered once rather than searched per line.
	var $index = 0.U64
	var $on_line = Dict.empty()
	for mark in marks {
		$on_line = Dict.insert($on_line, mark.line, (Dict.get($on_line, mark.line) ?? []).append($index))
		$index = $index + 1
	}
	var $rows = List.with_capacity(lines.len() + 8)
	var $number = 1.U64
	for _ in lines {
		found = Dict.get($on_line, $number.to_i64_wrap()) ?? []
		$rows = $rows.append(Line($number, found))
		for at in found {
			mark = marks.get(at) ?? empty_mark
			if mark.status == "fail" {
				$rows = $rows.append(Hint(at))
				if !mark.assertions.is_empty() {
					$rows = $rows.append(AssertHead(at))
					var $row = 0.U64
					for _ in mark.assertions {
						$rows = $rows.append(Assert(at, $row))
						$row = $row + 1
					}
				}
			}
		}
		$number = $number + 1
	}
	$rows
}

empty_mark : Mark
empty_mark = { ordinal: 0, line: 0, kind: "", role: "", status: "", duration: None, cycles: 0, patch: "", expected_count: None, observed_count: None, expected_patch: "", observed_patch: "", diagnostic: "", samples: [], assertions: [] }

## Classes, by byte: 0 plain, 1 parenthesis, 2 head, 3 keyword, 4 literal, 5 comment.
class_of : U8 -> [Plain, Paren, Head, Keyword, Literal, Comment]
class_of = |code| match code {
	1 => Paren
	2 => Head
	3 => Keyword
	4 => Literal
	5 => Comment
	_ => Plain
}

is_delimiter : U8 -> Bool
is_delimiter = |byte| byte == ' ' or byte == '\t' or byte == '(' or byte == ')' or byte == '"' or byte == ';'

is_digit : U8 -> Bool
is_digit = |byte| byte >= '0' and byte <= '9'

tokens : Str -> List({ text : Str, class : [Plain, Paren, Head, Keyword, Literal, Comment] })
tokens = |line| {
	bytes = line.to_utf8()
	# Modes: 0 between tokens, 1 in a string, 2 after a string's backslash,
	# 3 in a comment, 4 in an atom.
	var $mode = 0.U8
	var $atom = 0.U8
	var $opened = False
	var $classes = List.with_capacity(bytes.len())
	for byte in bytes {
		if $mode == 4 and is_delimiter(byte) {
			$mode = 0
		}
		code = if $mode == 3 {
			5.U8
		} else if $mode == 1 {
			if byte == '\\' {
				$mode = 2
			} else if byte == '"' {
				$mode = 0
			}
			4
		} else if $mode == 2 {
			$mode = 1
			4
		} else if $mode == 4 {
			$atom
		} else if byte == ';' {
			$mode = 3
			5
		} else if byte == '"' {
			$mode = 1
			$opened = False
			4
		} else if byte == '(' {
			$opened = True
			1
		} else if byte == ')' {
			$opened = False
			1
		} else if byte == ' ' or byte == '\t' {
			0
		} else {
			$mode = 4
			$atom = if byte == ':' 3 else if $opened 2 else if is_digit(byte) 4 else 0
			$opened = False
			$atom
		}
		$classes = $classes.append(code)
	}
	var $runs = []
	var $start = 0.U64
	var $index = 0.U64
	for code in $classes {
		if $index > $start and ($classes.get($start) ?? 0) != code {
			$runs = $runs.append({ text: Str.from_utf8_lossy(bytes.sublist({ start: $start, len: $index - $start })), class: class_of($classes.get($start) ?? 0) })
			$start = $index
		}
		$index = $index + 1
	}
	if $index > $start {
		$runs = $runs.append({ text: Str.from_utf8_lossy(bytes.sublist({ start: $start, len: $index - $start })), class: class_of($classes.get($start) ?? 0) })
	}
	$runs
}

expect tokens("") == []
expect {
	found = tokens("  (click (role button :name \"Open\")) ; go")
	found.map(|token| token.text) == ["  ", "(", "click", " ", "(", "role", " button ", ":name", " ", "\"Open\"", "))", " ", "; go"]
	and found.map(|token| token.class) == [Plain, Paren, Head, Plain, Paren, Head, Plain, Keyword, Plain, Literal, Paren, Plain, Comment]
}
expect tokens("(benchmark :warmups 2)").map(|token| token.class) == [Paren, Head, Plain, Keyword, Plain, Literal, Paren]
expect tokens("\"a \\\" b\" x").map(|token| token.text) == ["\"a \\\" b\"", " x"]
