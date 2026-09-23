## The annotated specification (W4, US-19 to US-21): the `.scm` source with a
## gutter per line of step status, duration, cycle count, and patch kind, each
## figure from its measurement family or a `—` that says why. A failing line is
## marked, with its diagnostic and its assertions' expected and observed values
## below it. Lines are built only near the viewport, so a specification of any
## length costs what a screenful does.
import pf.Gui
import Capture
import Format
import Observatory
import SpecSource
import Theme
import Widgets

Elem : Gui.Elem(Observatory.State)

SourceView := [].{
	## The source bar: the button granting a folder of sources, and what the
	## folder holds for this capture.
	bar : Observatory.State, Capture.Opened -> List(Elem)
	bar = bar

	## The median key of the run selector, offered when the capture has
	## samples and the source is annotated.
	median_key : Observatory.State, Capture.Opened -> List(Elem)
	median_key = median_key

	## Whether the run selector's key for a run is the one annotated.
	shows_run : Observatory.State, I64 -> Bool
	shows_run = |state, run_id| match state.spec_source.annotation {
		Some(annotation) => annotation.mode == OneRun(run_id)
		None => state.run == run_id
	}

	## The annotated source and the inspector of its chosen step.
	annotated : Observatory.State, Capture.Opened -> Elem
	annotated = annotated

	## Whether two states show the same source, compared by the reading that
	## produced it rather than its lines and marks.
	same : Observatory.State, Observatory.State -> Bool
	same = |a, b| {
		read = |state| match state.spec_source.annotation {
			Some(annotation) => annotation.read
			None => 0
		}
		folder = |state| match state.spec_source.folder {
			Some(held) => held.name
			None => ""
		}
		a.spec_source.of == b.spec_source.of and folder(a) == folder(b) and read(a) == read(b) and found_key(a.spec_source.found) == found_key(b.spec_source.found) and a.spec_source.chosen == b.spec_source.chosen and a.spec_source.scroll == b.spec_source.scroll and a.spec_source.reading == b.spec_source.reading
	}
}

found_key : SpecSource.Found -> Str
found_key = |found| match found {
	Unchecked => "unchecked"
	Unnamed => "unnamed"
	Missing(missing) => "missing ${missing.folder}"
	Matched(held) => "matched ${held.folder}/${held.file}"
	Changed(held) => "changed ${held.folder}/${held.file}"
}

median_key : Observatory.State, Capture.Opened -> List(Elem)
median_key = |state, opened| {
	annotation_mode = match state.spec_source.annotation {
		Some(annotation) => Some(annotation.mode)
		None => None
	}
	if Observatory.annotated(state) and !SpecSource.samples(opened).is_empty() {
		[Widgets.key({ caption: "median of samples", label: "Run median", selected: annotation_mode == Some(Median), on_press: |current, _| Observatory.ask(current, Annotate(Median)) })]
	} else {
		[]
	}
}

open_key : Elem
open_key = Widgets.key({ caption: "Open spec sources…", label: "Open spec sources", selected: False, on_press: |current, _| Observatory.ask(current, OpenSources) })

bar : Observatory.State, Capture.Opened -> List(Elem)
bar = |state, opened| {
	current = state.spec_source.of == opened.revision
	status = |label, text, ink| Widgets.labelled_note(label, text, ink)
	if Str.is_empty(Capture.metadata(opened, "spec_hash")) {
		[status("Source", "This capture ran no specification file, so it has no source to show.", Theme.dim)]
	} else if state.spec_source.folder == None {
		[Gui.row({ label: "Source bar", width: Fill, padding: 0, gap: Theme.inset, align: Center }, [open_key, status("Source", "Grant the folder of specification sources to see the steps on their lines.", Theme.dim)])]
	} else if !current {
		[Gui.row({ label: "Source bar", width: Fill, padding: 0, gap: Theme.inset, align: Center }, [open_key, status("Source", "Looking for this capture's specification…", Theme.dim)])]
	} else {
		shown = match state.spec_source.found {
			Matched(held) => [
				Widgets.chip(held.file, Theme.ink),
				Widgets.chip("✓ matches spec_hash", Theme.good),
				Widgets.meta("in ${held.folder}"),
			]
			Changed(held) => [
				Widgets.chip(held.file, Theme.ink),
				Widgets.chip("✗ hash differs from spec_hash", Theme.alarm_ink),
			]
			Missing(missing) => [status("Source", "None of the ${missing.files.to_str()} .scm files in ${missing.folder} hashes to spec_hash or declares \"${Capture.metadata(opened, "spec_name")}\".", Theme.caution)]
			Unnamed => [status("Source", "This capture names no specification.", Theme.dim)]
			Unchecked => []
		}
		banner = match state.spec_source.found {
			Changed(held) => [
				Gui.panel(
					{ label: "Specification changed", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, border_color: Theme.alarm_line, border_width: 1, radius: Theme.radius },
					[
						Gui.styled_text({ value: "Specification changed since capture", fg: Theme.alarm_ink, font_weight: 600 }),
						Gui.styled_text({ value: "${held.file} declares this capture's test, but its bytes no longer hash to spec_hash, so no result is placed on its lines. The steps are listed by the line they ran from.", fg: Theme.alarm_ink }),
					],
				),
			]
			_ => []
		}
		[Gui.row({ label: "Source bar", width: Fill, padding: 0, gap: Theme.inset, align: Center }, [open_key].concat(shown))].concat(banner)
	}
}

## Gutter widths.
status_width = 28.U32
duration_width = 96.U32
cycles_width = 64.U32
patch_width = 84.U32
number_width = 60.U32
gutter_width = status_width + duration_width + cycles_width + patch_width + number_width

## An absent figure: a `—` that says why, and opens Health at its family.
dash : Str, Str, U32 -> Elem
dash = |family_name, why, width| Widgets.holder(
	width,
	[
		Gui.tooltip(
			Gui.button({
				caption: "—",
				label: "Why ${family_name}",
				on_press: |current, _| Observatory.ask(current, ShowFamily(family_name)),
				padding: 0,
				font_size: Theme.body,
				font_face: Theme.face,
				radius: 0,
				bg: Theme.card,
				hover_bg: Theme.quiet_hover,
				active_bg: Theme.quiet_active,
				fg: Theme.ink,
				border_width: 0,
			}),
			why,
		),
	],
)

## The duration a line shows: its steps' durations together, each the run's
## or the samples' median. A step with no recorded duration leaves the line's
## total unknown, and it is shown so rather than as a smaller sum.
duration_cell : Capture.Opened, List(SpecSource.Mark) -> Elem
duration_cell = |opened, marks| if !Capture.complete(opened, "step_results") {
	dash("step_results", Capture.absence(opened, "step_results"), duration_width)
} else {
	durations = marks.keep_if(|mark| mark.duration != None)
	if durations.len() == marks.len() {
		total = durations.fold(0.I64, |sum, mark| sum + (match mark.duration { Some(ns) => ns, None => 0 }))
		Widgets.figure_cell(Format.ms(total), duration_width, Theme.ink)
	} else {
		untimed = marks.len() - durations.len()
		Widgets.holder(duration_width, [Gui.tooltip(Gui.row({ width: Fill, padding: 0, gap: 0, justify: End, fg: Theme.dim }, [Gui.text("—")]), "${untimed.to_str()} of the ${marks.len().to_str()} steps on this line recorded no duration, so the line has no total")])
	}
}

## Each patch kind once, in the order the steps met it.
patch_kinds : List(SpecSource.Mark) -> Str
patch_kinds = |marks| {
	var $kinds = []
	for mark in marks {
		for kind in Str.split_on(mark.patch, ",") {
			if !Str.is_empty(kind) and !$kinds.contains(kind) {
				$kinds = $kinds.append(kind)
			}
		}
	}
	if $kinds.is_empty() "—" else Str.join_with($kinds, ",")
}

cycles_cells : Capture.Opened, SpecSource.Annotation, List(SpecSource.Mark) -> List(Elem)
cycles_cells = |opened, annotation, marks| {
	absent = marks.fold(
		Recorded,
		|found, mark| match found {
			Absent(why) => Absent(why)
			Recorded => SpecSource.cycles_absence(opened, annotation.boundary, mark)
		},
	)
	match absent {
		Recorded => {
			cycles = marks.fold(0.I64, |sum, mark| sum + mark.cycles)
			[
				Widgets.figure_cell(cycles.to_str(), cycles_width, if cycles == 0 Theme.dim else Theme.ink),
				Widgets.cell(patch_kinds(marks), patch_width, Theme.dim),
			]
		}
		Absent(why) => [dash("host_cycles", why, cycles_width), dash("host_cycles", why, patch_width)]
	}
}

## One source line in styled runs.
code : Str -> Elem
code = |line| {
	spans = SpecSource.tokens(line).map(
		|token| match token.class {
			Paren => Gui.span({ text: token.text, fg: Theme.dim })
			Head => Gui.span({ text: token.text, fg: Theme.accent, font_weight: 600 })
			Keyword => Gui.span({ text: token.text, fg: Theme.code_keyword })
			Literal => Gui.span({ text: token.text, fg: Theme.code_literal })
			Comment => Gui.span({ text: token.text, fg: Theme.dim })
			Plain => Gui.span({ text: token.text })
		},
	)
	Gui.row(
		{ width: Fill, grow: True, overflow_x: Clip, padding: 0, gap: 0, font_size: Theme.body, font_face: Theme.face, text_overflow: NoWrap, align: Center },
		[Gui.rich_text({ spans, fg: Theme.ink })],
	)
}

source_row : { label : Str, bg : Gui.Color }, List(Elem) -> Elem
source_row = |props, cells| Gui.row(
	{ label: props.label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: props.bg },
	cells,
)

## The rows below a failing line sit under its source, past the gutter.
under_gutter : Str, Gui.Color, List(Elem) -> Elem
under_gutter = |label, bg, cells| source_row({ label, bg }, [Gui.row({ width: Px(gutter_width), min_width: Px(gutter_width), padding: 0, gap: 0 }, [])].concat(cells))

figure : [None, Some(I64)] -> Str
figure = |value| Format.maybe_int(value)

line_row : Observatory.State, Capture.Opened, SpecSource.Annotation, List(Str), U64, List(U64) -> Elem
line_row = |state, opened, annotation, lines, number, found| {
	text = lines.get(number - 1) ?? ""
	chosen = state.spec_source.chosen == Some(number)
	number_key = Widgets.row_key({
		caption: number.to_str(),
		label: "Line ${number.to_str()}",
		selected: chosen,
		on_press: |current, _| Gui.update({ ..current, spec_source: { ..current.spec_source, chosen: Some(number) } }),
	})
	label = "Source line ${number.to_str()}"
	if found.is_empty() {
		blank = gutter_width - number_width
		source_row({ label, bg: if chosen Theme.selected else Theme.card }, [Gui.row({ width: Px(blank), min_width: Px(blank), padding: 0, gap: 0 }, []), Widgets.holder(number_width, [number_key]), code(text)])
	} else {
		marks = found.map(|at| annotation.marks.get(at) ?? empty_mark)
		pass = marks.all(|mark| mark.status == "pass")
		bg = if !pass Theme.alarm else if chosen Theme.selected else Theme.card
		source_row(
			{ label, bg },
			[Widgets.cell(Widgets.pass_mark(pass), status_width, Widgets.pass_ink(pass)), duration_cell(opened, marks)]
				.concat(cycles_cells(opened, annotation, marks))
				.concat([Widgets.holder(number_width, [number_key]), code(text)]),
		)
	}
}

empty_mark : SpecSource.Mark
empty_mark = { ordinal: 0, line: 0, kind: "", role: "", status: "", duration: None, cycles: 0, patch: "", expected_count: None, observed_count: None, expected_patch: "", observed_patch: "", diagnostic: "", samples: [], assertions: [] }

## A step's expected and observed count and patch, when it asserts them.
expectations : SpecSource.Mark -> List(Str)
expectations = |mark| {
	count = match (mark.expected_count, mark.observed_count) {
		(Some(expected), observed) => ["expected count ${expected.to_str()}, observed ${figure(observed)}"]
		_ => []
	}
	patch = if Str.is_empty(mark.expected_patch) [] else ["expected patch ${mark.expected_patch}, observed ${mark.observed_patch}"]
	count.concat(patch)
}

hint_row : SpecSource.Annotation, U64 -> Elem
hint_row = |annotation, index| {
	mark = annotation.marks.get(index) ?? empty_mark
	why = Str.join_with([mark.diagnostic].concat(expectations(mark)).keep_if(|part| !Str.is_empty(part)), " · ")
	under_gutter("Hint line ${mark.line.to_str()}", Theme.alarm, [Widgets.rest_cell("┆ ${if Str.is_empty(why) "failed" else why}", Theme.alarm_ink)])
}

assertion_width = 220.U32

assert_head : SpecSource.Annotation, U64 -> Elem
assert_head = |annotation, index| {
	mark = annotation.marks.get(index) ?? empty_mark
	under_gutter(
		"Assertions line ${mark.line.to_str()}",
		Theme.alarm,
		[Widgets.cell("┆ assertion", assertion_width, Theme.dim), Widgets.figure_cell("expected", 90, Theme.dim), Widgets.figure_cell("observed", 90, Theme.dim)],
	)
}

assert_row : SpecSource.Annotation, U64, U64 -> Elem
assert_row = |annotation, index, at| {
	mark = annotation.marks.get(index) ?? empty_mark
	value = mark.assertions.get(at) ?? { group: "", name: "", expected: None, observed: None }
	# An assertion without an expected value asserts nothing of it.
	mismatch = value.expected != None and value.expected != value.observed
	ink = if mismatch Theme.alarm_ink else Theme.ink
	under_gutter(
		"Assertion ${value.group} ${value.name} line ${mark.line.to_str()}",
		Theme.alarm,
		[
			Widgets.cell("┆ ${value.group} · ${value.name}", assertion_width, ink),
			Widgets.figure_cell(figure(value.expected), 90, ink),
			Widgets.figure_cell(figure(value.observed), 90, ink),
			Widgets.cell(if mismatch "✗" else "", 30, Theme.alarm_ink),
		],
	)
}

## A line of the inspector, wrapped rather than clipped.
wrapped : Str, Str, Gui.Color -> Elem
wrapped = |label, text, ink| Gui.col({ label, width: Fill, padding: 0, gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Wrap }, [Gui.text(text)])

cycle_count : I64 -> Str
cycle_count = |count| if count == 1 "1 cycle" else "${count.to_str()} cycles"

## One step of the chosen line: its identity and result, and in the median
## every sample's own values.
step_detail : Capture.Opened, SpecSource.Annotation, SpecSource.Mark -> List(Elem)
step_detail = |opened, annotation, mark| {
	timed = Capture.complete(opened, "step_results")
	duration = if timed Format.maybe_ms(mark.duration) else "—"
	recorded = SpecSource.cycles_absence(opened, annotation.boundary, mark) == Recorded
	cycles = match SpecSource.cycles_absence(opened, annotation.boundary, mark) {
		Recorded => "${cycle_count(mark.cycles)} · ${if Str.is_empty(mark.patch) "no patch" else mark.patch}"
		Absent(why) => "cycles —: ${why}"
	}
	samples = if mark.samples.is_empty() {
		[]
	} else {
		[Widgets.heading("SAMPLES · median shown")].concat(
			mark.samples.map(|sample| wrapped("Sample ${sample.index.to_str()}", "sample ${sample.index.to_str()} · run ${sample.run.to_str()} · ${if timed Format.maybe_ms(sample.duration) else "—"} · ${if recorded cycle_count(sample.cycles) else "cycles —"} · ${sample.status}", if sample.status == "pass" Theme.ink else Theme.alarm_ink)),
		)
	}
	[
		wrapped("Step kind", "${mark.ordinal.to_str()} · ${mark.kind}", Theme.ink),
		wrapped("Step role", "role ${mark.role}", Theme.dim),
		wrapped("Step result", "${mark.status} · ${duration}", if mark.status == "pass" Theme.good else Theme.alarm_ink),
		wrapped("Step cycles", cycles, Theme.ink),
	]
		.concat(expectations(mark).map(|text| wrapped("Step expectation", text, Theme.ink)))
		.concat(if Str.is_empty(mark.diagnostic) [] else [Gui.col({ label: "Step diagnostic", width: Fill, padding: 0, gap: 0, fg: Theme.alarm_ink, font_size: Theme.body, text_overflow: Wrap }, [Gui.text(mark.diagnostic)])])
		.concat(samples)
}

inspector_width = 300.U32

## The steps of the chosen line.
inspector : Observatory.State, Capture.Opened, SpecSource.Annotation -> Elem
inspector = |state, opened, annotation| {
	body = match state.spec_source.chosen {
		None => [Widgets.note("Press a line number to inspect its steps.")]
		Some(number) => {
			marks = annotation.marks.keep_if(|mark| mark.line == number.to_i64_wrap())
			title = Widgets.labelled_note("Step title", "LINE ${number.to_str()} · ${marks.len().to_str()} ${if marks.len() == 1 "step" else "steps"}", Theme.dim)
			if marks.is_empty() {
				[title, Widgets.note("No step ran from this line.")]
			} else {
				[title].concat(marks.map(|mark| step_detail(opened, annotation, mark)).join())
			}
		}
	}
	Gui.scroll({
		label: "Step inspector",
		width: Px(inspector_width),
		min_width: Px(inspector_width),
		height: Fill,
		bg: Theme.card,
		border_color: Theme.line,
		border_width: 1,
		radius: Theme.radius,
		content: Gui.col({ width: Px(inspector_width - 2), max_width: Px(inspector_width - 2), padding: Theme.inset, gap: 4 }, body),
	})
}

annotated : Observatory.State, Capture.Opened -> Elem
annotated = |state, opened| match (state.spec_source.annotation, state.spec_source.found) {
	(Some(annotation), Matched(held)) => {
		lines = held.lines
		render_row : U64 -> Elem
		render_row = |index| match annotation.rows.get(index) {
			Ok(Line(number, found)) => line_row(state, opened, annotation, lines, number, found)
			Ok(Hint(at)) => hint_row(annotation, at)
			Ok(AssertHead(at)) => assert_head(annotation, at)
			Ok(Assert(at, row)) => assert_row(annotation, at, row)
			Err(_) => source_row({ label: "", bg: Theme.card }, [])
		}
		Gui.row(
			{ label: "Annotated source", width: Fill, height: Fill, grow: True, min_height: Px(0), padding: 0, gap: Theme.inset },
			[
				Gui.col(
					{ label: "Source table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
					[
						Widgets.table_head(
							"Source columns",
							[Widgets.head_cell("st", status_width), Widgets.head_figure("duration", duration_width), Widgets.head_figure("cycles", cycles_width), Widgets.head_cell("patch", patch_width), Widgets.head_figure("line", number_width), Widgets.head_rest("${held.file} · ${lines.len().to_str()} lines")],
						),
						Gui.virtual_rows({
							label: "Source",
							row_height: Theme.row_height,
							count: annotation.rows.len(),
							render_row,
							scroll_to: state.spec_source.scroll,
						}),
					],
				),
				inspector(state, opened, annotation),
			],
		)
	}
	_ => Widgets.note("Reading the steps of this run…")
}
