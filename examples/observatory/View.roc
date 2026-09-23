## The mounted instrument: a header, the folder authority, the capture list, and
## for an open capture its bar, health banner, view rail, and the chosen view.
## Every figure is drawn from a measurement family; a family that is not
## `complete` is drawn as `—` with its status and reason beside it.
import pf.Gui
import Capture
import Format
import Observatory
import Theme

View := [].{
	render : Observatory.State -> Gui.Elem(Observatory.State)
	render = render
}

## Text

meta : Str -> Gui.Elem(Observatory.State)
meta = |caption| Gui.row(
	{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

note : Str -> Gui.Elem(Observatory.State)
note = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta },
	[Gui.text(caption)],
)

line : Str -> Gui.Elem(Observatory.State)
line = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
	[Gui.text(caption)],
)

heading : Str -> Gui.Elem(Observatory.State)
heading = |caption| Gui.row(
	{ width: Fill, padding: 0, padding_top: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

verdict_ink : Capture.Verdict -> Gui.Color
verdict_ink = |verdict| match verdict {
	Complete => Theme.good
	Partial(_) => Theme.caution
	Untrusted(_) => Theme.alarm_ink
	Unsupported(_) => Theme.alarm_ink
}

verdict_badge : Capture.Verdict -> Str
verdict_badge = |verdict| match verdict {
	Complete => "✓ complete"
	Partial(_) => "⚠ partial"
	Untrusted(_) => "✗ untrusted"
	Unsupported(reason) => "✗ ${reason}"
}

## Tables. A cell clips rather than wraps, so every row is one line tall and a
## column's figures sit on the same vertical rule as its heading.

cell : Str, U32, Gui.Color -> Gui.Elem(Observatory.State)
cell = |text, width, ink| Gui.row(
	{ width: Px(width), padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
	[Gui.text(text)],
)

figure_cell : Str, U32 -> Gui.Elem(Observatory.State)
figure_cell = |text, width| Gui.row(
	{ width: Px(width), padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis, align: Center, justify: End },
	[Gui.text(text)],
)

rest_cell : Str, Gui.Color -> Gui.Elem(Observatory.State)
rest_cell = |text, ink| Gui.row(
	{ width: Fill, grow: True, padding: 0, gap: 0, fg: ink, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis, align: Center },
	[Gui.text(text)],
)

table_row : List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table_row = |cells| Gui.row(
	{ width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

table_head : Str, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table_head = |label, cells| Gui.row(
	{ label, width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	cells,
)

head_cell : Str, U32 -> Gui.Elem(Observatory.State)
head_cell = |text, width| Gui.row(
	{ width: Px(width), padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center },
	[Gui.text(text)],
)

head_figure : Str, U32 -> Gui.Elem(Observatory.State)
head_figure = |text, width| Gui.row(
	{ width: Px(width), padding: 0, padding_right: Px(Theme.inset), gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center, justify: End },
	[Gui.text(text)],
)

head_rest : Str -> Gui.Elem(Observatory.State)
head_rest = |text| Gui.row(
	{ width: Fill, grow: True, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center },
	[Gui.text(text)],
)

table : Str, List(Gui.Elem(Observatory.State)) -> Gui.Elem(Observatory.State)
table = |label, children| Gui.col(
	{ label, width: Fill, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
	children,
)

## Controls

key : { caption : Str, label : Str, selected : Bool, on_press : Observatory.State, Gui.EventPress => Gui.Action(Observatory.State) } -> Gui.Elem(Observatory.State)
key = |props| Gui.button({
	caption: props.caption,
	label: props.label,
	on_press: props.on_press,
	padding: 6,
	font_size: Theme.body,
	font_face: Theme.face,
	radius: Theme.radius,
	bg: if props.selected Theme.accent else Theme.quiet,
	hover_bg: if props.selected Theme.accent_hover else Theme.quiet_hover,
	active_bg: if props.selected Theme.accent_active else Theme.quiet_active,
	fg: if props.selected Theme.on_accent else Theme.ink,
	border_color: Theme.line,
	border_width: 1,
	text_overflow: Ellipsis,
})

## Header and authority

header : Observatory.State -> Gui.Elem(Observatory.State)
header = |state| {
	right = match state.status {
		Busy(_) => "reading…"
		_ => match state.capture {
			Some(opened) => opened.name
			None => "no capture open"
		}
	}
	Gui.row(
		{ label: "Observatory header", width: Fill, padding: Theme.inset, gap: 8, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1), fg: Theme.ink, font_size: Theme.meta },
		[
			Gui.text("OBSERVATORY"),
			meta("roc-gui captures, schema ${Capture.supported_schema}, read only"),
			Gui.row({ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(right)]),
		],
	)
}

authority_bar : Observatory.State -> Gui.Elem(Observatory.State)
authority_bar = |state| {
	reading = match state.grant {
		Ungranted => { held: "no folder granted", verdict: "choose a folder of captures", ink: Theme.dim }
		Declined => { held: "no folder granted", verdict: "you closed the picker without choosing", ink: Theme.dim }
		Granted(folder) => { held: folder, verdict: "read-only, this folder only", ink: Theme.ink }
		Refused => { held: "no folder granted", verdict: "the host refused a folder", ink: Theme.alarm_ink }
	}
	Gui.row(
		{ label: "Authority bar", width: Fill, padding: Theme.inset, gap: Theme.inset, align: Center, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_bottom: Px(1), font_size: Theme.meta },
		[
			meta("FOLDER"),
			Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.meta, font_face: Theme.face, max_width: Px(320), text_overflow: Ellipsis }, [Gui.text(reading.held)]),
			Gui.row({ label: "Folder verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta }, [Gui.text(reading.verdict)]),
			key({ caption: "Open folder…", label: "Open folder", selected: False, on_press: |current, _| Observatory.choose(current) }),
		],
	)
}

error_band : Observatory.State -> Gui.Elem(Observatory.State)
error_band = |state| match state.status {
	Failed(problem) => Gui.panel(
		{ label: "Capture error", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, fg: Theme.alarm_ink, border_color: Theme.alarm_line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[
			Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text(problem.message)]),
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Gui.text(problem.remedy)]),
		],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

## The capture list (W0)

capture_row : Gui.FilesDirRead, Capture.Listing -> Gui.Elem(Observatory.State)
capture_row = |directory, listing| Gui.row(
	{ label: "Capture row ${listing.name}", width: Fill, height: Px(Theme.row_height), padding: 0, padding_left: Px(Theme.inset), gap: 0, align: Center, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[
		Gui.row(
			{ width: Px(250), padding: 0, padding_right: Px(Theme.inset), gap: 0 },
			[
				Gui.button({
					caption: listing.name,
					label: "Capture ${listing.name}",
					on_press: |current, _| Observatory.open_capture(current, directory, listing.name),
					width: Fill,
					padding: 3,
					font_size: Theme.body,
					font_face: Theme.face,
					radius: Theme.radius,
					bg: Theme.quiet,
					hover_bg: Theme.quiet_hover,
					active_bg: Theme.quiet_active,
					fg: Theme.ink,
					border_color: Theme.line,
					border_width: 1,
					text_overflow: Ellipsis,
				}),
			],
		),
		cell(listing.application, 150, Theme.ink),
		cell(listing.spec, 260, Theme.ink),
		cell(listing.backend, 150, Theme.dim),
		figure_cell(listing.scale, 70),
		cell(listing.detail, 80, Theme.dim),
		rest_cell(verdict_badge(listing.verdict), verdict_ink(listing.verdict)),
	],
)

capture_list : Observatory.State -> Gui.Elem(Observatory.State)
capture_list = |state| {
	body = match state.folder {
		None => [note("Choose a folder of .rgstats captures, such as a benchmark output directory.")]
		Some(folder) => if folder.captures.is_empty() {
			[note("The folder holds no .rgstats captures.")]
		} else {
			[
				meta("CAPTURES IN ${folder.name} · ${folder.captures.len().to_str()}"),
				Gui.col(
					{ label: "Capture table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
					[
						table_head("Capture columns", [head_cell("file", 250), head_cell("app", 150), head_cell("spec", 260), head_cell("backend", 150), head_figure("scale", 70), head_cell("detail", 80), head_rest("health")]),
						Gui.virtual_list({
							label: "Captures",
							row_height: Theme.row_height,
							items: folder.captures.map_with_index(|listing, index| { key: index, content: capture_row(folder.directory, listing) }),
						}),
					],
				),
			]
		}
	}
	Gui.col(
		{ label: "Start", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset, bg: Theme.paper },
		body,
	)
}

## The capture bar and the health banner (US-6)

chip : Str, Gui.Color -> Gui.Elem(Observatory.State)
chip = |text, ink| Gui.row(
	{ padding: 3, padding_left: Px(6), padding_right: Px(6), gap: 0, fg: ink, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(text)],
)

capture_bar : Capture.Opened -> Gui.Elem(Observatory.State)
capture_bar = |opened| {
	final = Capture.metadata(opened, "final_state")
	clean = Capture.metadata(opened, "clean_shutdown")
	gaps = opened.gaps.len()
	Gui.row(
		{ label: "Capture bar", width: Fill, padding: Theme.inset, gap: 6, align: Center, bg: Theme.paper, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		[
			key({ caption: "‹ Captures", label: "Back to captures", selected: False, on_press: |current, _| Gui.update(Observatory.close_capture(current)) }),
			Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, max_width: Px(260), text_overflow: Ellipsis }, [Gui.text(opened.name)]),
			chip(Capture.metadata(opened, "backend"), Theme.ink),
			chip(Capture.metadata(opened, "effective_detail"), Theme.ink),
			chip("schema ${Capture.metadata(opened, "schema_version")}", Theme.ink),
			chip(if final == "complete" "✓ final" else "not finalised", if final == "complete" Theme.good else Theme.alarm_ink),
			chip(if clean == "1" "clean shutdown" else "unclean shutdown", if clean == "1" Theme.good else Theme.alarm_ink),
			chip("gaps ${gaps.to_str()}", if gaps == 0 Theme.good else Theme.alarm_ink),
			chip(Capture.metadata(opened, "timing_quality"), if Capture.metadata(opened, "timing_quality") == "isolated" Theme.ink else Theme.caution),
			Gui.row({ padding: 0, gap: 0, grow: True, justify: End }, [chip(verdict_badge(opened.verdict), verdict_ink(opened.verdict))]),
		],
	)
}

banner : Capture.Opened -> Gui.Elem(Observatory.State)
banner = |opened| match opened.verdict {
	Untrusted(cause) => Gui.panel(
		{ label: "Untrusted capture", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.alarm, fg: Theme.alarm_ink, border_color: Theme.alarm_line, border_width: 0, border_bottom: Px(1), radius: 0 },
		[Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text("Untrusted capture: ${cause}")])],
	)
	_ => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

nav : Observatory.State -> Gui.Elem(Observatory.State)
nav = |state| {
	entry = |caption, view| key({ caption, label: caption, selected: state.view == view, on_press: |current, _| Gui.update(Observatory.show(current, view)) })
	Gui.col(
		{ label: "Views", width: Px(Theme.nav_width), height: Fill, padding: Theme.inset, gap: 6, bg: Theme.rail, border_color: Theme.line, border_width: 0, border_right: Px(1) },
		[meta("VIEWS"), entry("Overview", Overview), entry("Interactions", Interactions), entry("Spec", Spec), entry("Health", Health)],
	)
}

## Overview (W1)

tile : { name : Str, value : Str, detail : Str, opens : Str, view : Observatory.View } -> Gui.Elem(Observatory.State)
tile = |props| Gui.panel(
	{ label: "Tile ${props.name}", width: Px(Theme.tile_width), padding: Theme.inset, gap: 4, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
	[
		meta(props.name),
		Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.figure, font_face: Theme.face, text_overflow: Ellipsis }, [Gui.text(props.value)]),
		Gui.row({ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, text_overflow: Ellipsis }, [Gui.text(props.detail)]),
		key({ caption: "${props.opens} ›", label: "Open ${props.name}", selected: False, on_press: |current, _| Gui.update(Observatory.show(current, props.view)) }),
	],
)

## A figure from one family: its value when the family is complete, otherwise
## `—` and the family's status and reason.
measured : Capture.Opened, Str, { value : Str, detail : Str } -> { value : Str, detail : Str }
measured = |opened, name, present| if Capture.complete(opened, name) present else { value: "—", detail: Capture.absence(opened, name) }

identity : Capture.Opened -> List(Gui.Elem(Observatory.State))
identity = |opened| {
	m = |name| Capture.metadata(opened, name)
	commit = m("host_commit")
	short = if Str.is_empty(commit) "unavailable" else Str.from_utf8(commit.to_utf8().take_first(7)) ?? commit
	dirty = match m("host_dirty") {
		"1" => " (dirty)"
		"0" => ""
		_ => " (dirty unknown)"
	}
	samples = m("benchmark_samples")
	benchmark = if samples == "0" or Str.is_empty(samples) {
		"not a benchmark: one test run"
	} else {
		"benchmark: ${m("benchmark_warmups")} warmups · ${samples} samples · ${m("benchmark_iterations")} iterations · scale ${m("benchmark_scale")}"
	}
	[
		line("${m("app_name")} · spec \"${m("spec_name")}\" · ${m("target_profile")}"),
		line("commit ${short}${dirty} · ${m("cpu_model")} ×${m("logical_cpu_count")} · ${m("host_os")} ${m("host_arch")}"),
		line(benchmark),
	]
}

overview : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
overview = |state, opened| {
	passed = opened.runs.keep_if(|run| run.outcome == "pass").len()
	outcome = measured(opened, "test_outcome", { value: "${passed.to_str()}/${opened.runs.len().to_str()} runs pass", detail: "${opened.steps.len().to_str()} steps" })
	phase_triggers = opened.triggers.keep_if(|trigger| trigger.phase == state.phase)
	slowest_found = List.sort_with(phase_triggers, |left, right| if left.median > right.median Before else if left.median < right.median After else Same).first()
	slowest = measured(
		opened,
		"host_cycles",
		match slowest_found {
			Ok(found) => { value: "${found.trigger}", detail: "${found.patch_kind} · median ${Format.ms(found.median)} · max ${Format.ms(found.max)}" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	median = measured(
		opened,
		"host_cycles",
		match opened.medians.find_first(|found| found.phase == state.phase) {
			Ok(found) => { value: Format.ms(found.median), detail: "${found.count.to_str()} ${state.phase} cycles" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	frames = measured(
		opened,
		"gpui_frame_spans",
		{ value: "${opened.frames.over_budget.to_str()} of ${opened.frames.drawn.to_str()}", detail: "host-owned stages over 16.7 ms" },
	)
	skip = measured(
		opened,
		"component_work",
		match opened.skips.find_first(|found| found.phase == state.phase) {
			Ok(found) => { value: Format.percent(found.skipped, found.compared), detail: "${found.skipped.to_str()} of ${found.compared.to_str()} compared skipped" }
			Err(_) => { value: "none", detail: "no ${state.phase} cycles" }
		},
	)
	Gui.col(
		{ label: "Overview", width: Fill, padding: Theme.inset, gap: 6 },
		[heading("IDENTITY")]
			.concat(identity(opened))
			.concat(
				[
					heading("${state.phase} phase"),
					Gui.row(
						{ label: "Tiles", width: Fill, padding: 0, gap: Theme.inset },
						[
							tile({ name: "Outcome", value: outcome.value, detail: outcome.detail, opens: "Spec", view: Spec }),
							tile({ name: "Slowest trigger", value: slowest.value, detail: slowest.detail, opens: "Interactions", view: Interactions }),
							tile({ name: "Median cycle", value: median.value, detail: median.detail, opens: "Interactions", view: Interactions }),
						],
					),
					Gui.row(
						{ label: "More tiles", width: Fill, padding: 0, gap: Theme.inset },
						[
							tile({ name: "Frames over budget", value: frames.value, detail: frames.detail, opens: "Health", view: Health }),
							tile({ name: "Skip rate", value: skip.value, detail: skip.detail, opens: "Health", view: Health }),
							tile({ name: "Verdict", value: Capture.verdict_word(opened.verdict), detail: Capture.verdict_reason(opened.verdict), opens: "Health", view: Health }),
						],
					),
				],
			),
	)
}

## Interactions (W2, the triggers table)

phases : List(Str)
phases = ["initialization", "setup", "measured", "interactive"]

interactions : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
interactions = |state, opened| {
	timed = Capture.complete(opened, "host_cycles")
	shown = |ns| if timed Format.ms(ns) else "—"
	rows = opened.triggers.keep_if(|trigger| trigger.phase == state.phase)
	selector = Gui.row(
		{ label: "Phase", width: Fill, padding: 0, gap: 6, align: Center },
		[meta("PHASE")].concat(phases.map(|phase| key({ caption: phase, label: "Phase ${phase}", selected: state.phase == phase, on_press: |current, _| Gui.update(Observatory.set_phase(current, phase)) }))),
	)
	body = if rows.is_empty() {
		[note("No cycles were recorded in the ${state.phase} phase.")]
	} else {
		rows.map(
			|trigger| table_row([
				cell(trigger.trigger, 180, Theme.ink),
				cell(trigger.patch_kind, 110, Theme.dim),
				figure_cell(if timed trigger.count.to_str() else "—", 70),
				figure_cell(shown(trigger.min), 110),
				figure_cell(shown(trigger.median), 110),
				figure_cell(shown(trigger.max), 110),
				figure_cell(shown(trigger.iqr), 110),
				rest_cell("", Theme.dim),
			]),
		)
	}
	absence = if timed [] else [note("Durations shown as — : ${Capture.absence(opened, "host_cycles")}")]
	Gui.col(
		{ label: "Interactions", width: Fill, padding: Theme.inset, gap: Theme.inset },
		[selector, heading("TRIGGERS · ${state.phase} · by median · warmups excluded")]
			.concat(absence)
			.concat(
				[
					table(
						"Triggers",
						[
							table_head("Trigger columns", [head_cell("trigger", 180), head_cell("patch", 110), head_figure("cycles", 70), head_figure("min", 110), head_figure("median", 110), head_figure("max", 110), head_figure("IQR", 110), head_rest("")]),
						].concat(body),
					),
				],
			),
	)
}

## Spec results (US-21)

run_caption : Capture.Run -> Str
run_caption = |run| {
	index = match run.sample {
		Some(sample) => " ${sample.to_str()}"
		None => ""
	}
	mark = if run.outcome == "pass" "✓" else if run.outcome == "fail" "✗" else "…"
	"${mark} ${run.phase}${index}"
}

step_result : Capture.Step -> Str
step_result = |step| {
	count = match (step.expected_count, step.observed_count) {
		(Some(expected), observed) => ["count ${expected.to_str()} / ${Format.maybe_int(observed)}"]
		(None, Some(observed)) => ["observed ${observed.to_str()}"]
		_ => []
	}
	patch = if Str.is_empty(step.expected_patch) [] else ["patch ${step.expected_patch} / ${step.observed_patch}"]
	diagnostic = if Str.is_empty(step.diagnostic) [] else [step.diagnostic]
	Str.join_with(count.concat(patch).concat(diagnostic), " · ")
}

spec : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
spec = |state, opened| {
	timed = Capture.complete(opened, "step_results")
	selector = Gui.row(
		{ label: "Run", width: Fill, padding: 0, gap: 6, align: Center },
		[meta("RUN")].concat(opened.runs.map(|run| key({ caption: run_caption(run), label: "Run ${run.id.to_str()}", selected: state.run == run.id, on_press: |current, _| Observatory.select_run(current, run.id) }))),
	)
	runs = table(
		"Runs",
		[table_head("Run columns", [head_figure("run", 50), head_cell("phase", 90), head_figure("index", 60), head_cell("outcome", 80), head_figure("steps", 60), head_figure("failed", 60), head_rest("diagnostic")])].concat(
			opened.runs.map(
				|run| table_row([
					figure_cell(run.id.to_str(), 50),
					cell(run.phase, 90, Theme.ink),
					figure_cell(Format.maybe_int(run.sample), 60),
					cell(run.outcome, 80, if run.outcome == "pass" Theme.good else Theme.alarm_ink),
					figure_cell(run.steps.to_str(), 60),
					figure_cell(run.failed.to_str(), 60),
					rest_cell(run.diagnostic, Theme.alarm_ink),
				]),
			),
		),
	)
	steps = opened.steps
	more = if opened.steps_more [note("The first ${Capture.step_page.to_str()} steps of this run are shown.")] else []
	step_rows = steps.map_with_index(
		|step, index| {
			key: index,
			content: table_row([
				cell("Step line ${step.line.to_str()}", 120, Theme.dim),
				cell(step.kind, 200, Theme.ink),
				cell(step.role, 90, Theme.dim),
				cell(step.status, 50, if step.status == "pass" Theme.good else Theme.alarm_ink),
				figure_cell(if timed Format.maybe_ms(step.duration) else "—", 110),
				rest_cell(step_result(step), if step.status == "pass" Theme.dim else Theme.alarm_ink),
			]),
		},
	)
	absence = if timed [] else [note("Durations shown as — : ${Capture.absence(opened, "step_results")}")]
	Gui.col(
		{ label: "Spec", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset },
		[selector, heading("RUNS"), runs, heading("STEPS OF RUN ${state.run.to_str()} · ${steps.len().to_str()}")]
			.concat(absence)
			.concat(more)
			.concat(
				[
					Gui.col(
						{ label: "Step table", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
						[
							table_head("Step columns", [head_cell("line", 120), head_cell("kind", 200), head_cell("role", 90), head_cell("status", 50), head_figure("duration", 110), head_rest("expected / observed · diagnostic")]),
							Gui.virtual_list({ label: "Steps", row_height: Theme.row_height, items: step_rows }),
						],
					),
				],
			),
	)
}

## Health (W9, US-8)

status_ink : Str -> Gui.Color
status_ink = |status| match status {
	"complete" => Theme.good
	"partial" => Theme.caution
	"unfinalized" => Theme.alarm_ink
	_ => Theme.dim
}

flag : I64 -> Str
flag = |value| if value == 0 "ok" else "failed"

health : Capture.Opened -> Gui.Elem(Observatory.State)
health = |opened| {
	families = table(
		"Measurement families",
		[table_head("Family columns", [head_cell("family", 230), head_cell("detail", 80), head_cell("status", 110), head_figure("rows", 70), head_figure("omitted", 80), head_rest("reason")])].concat(
			opened.families.map(
				|found| table_row([
					cell(found.name, 230, Theme.ink),
					cell(found.detail, 80, Theme.dim),
					cell(found.status, 110, status_ink(found.status)),
					figure_cell(found.rows.to_str(), 70),
					figure_cell(found.omitted.to_str(), 80),
					rest_cell(found.reason, Theme.dim),
				]),
			),
		),
	)
	gaps = table(
		"Recording gaps",
		if opened.gaps.is_empty() {
			[table_row([rest_cell("none", Theme.good)])]
		} else {
			[table_head("Gap columns", [head_cell("family", 230), head_figure("lost", 80), head_rest("reason")])].concat(
				opened.gaps.map(|gap| table_row([cell(gap.family, 230, Theme.ink), figure_cell(gap.lost.to_str(), 80), rest_cell(gap.reason, Theme.dim)])),
			)
		},
	)
	recorder = match opened.health {
		Some(found) => [
			line("transactions ${found.transactions.to_str()} · queue high water ${found.queue_high_water.to_str()} · output ${Format.bytes(found.output_bytes)} · rows ${found.rows_written.to_str()}"),
			line("omitted events ${found.omitted_events.to_str()} · writer ${flag(found.writer_failed)} · output limit ${if found.output_limited == 0 "not reached" else "reached"} · drain ${Format.ms(found.drain_ns)}"),
		]
		None => [line("The recorder health row is missing.")]
	}
	unavailable = Capture.metadata(opened, "unavailable_sources")
	Gui.col(
		{ label: "Health", width: Fill, padding: Theme.inset, gap: 6 },
		[
			Gui.row(
				{ label: "Verdict", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[meta("VERDICT"), Gui.row({ padding: 0, gap: 0, fg: verdict_ink(opened.verdict), font_size: Theme.body, font_face: Theme.face }, [Gui.text(Capture.verdict_word(opened.verdict))]), line(Capture.verdict_reason(opened.verdict))],
			),
			note(Capture.rule),
			heading("MEASUREMENT FAMILIES"),
			families,
			heading("RECORDING GAPS"),
			gaps,
			heading("RECORDER HEALTH"),
			Gui.panel({ label: "Recorder health", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius }, recorder),
			heading("IDENTITY · ${opened.metadata.len().to_str()} keys"),
			Gui.panel(
				{ label: "Identity", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
				opened.metadata.map(|entry| line("${entry.key} = ${entry.value}")),
			),
			heading("UNAVAILABLE SOURCES"),
			Gui.col(
				{ label: "Unavailable sources", width: Fill, padding: 0, gap: 2 },
				if Str.is_empty(unavailable) [note("none declared")] else Str.split_on(unavailable, ",").map(|source| line(source)),
			),
		],
	)
}

scrolled : Str, Gui.Elem(Observatory.State) -> Gui.Elem(Observatory.State)
scrolled = |label, content| Gui.scroll({ label, content, width: Fill, height: Fill, grow: True })

main_view : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
main_view = |state, opened| match state.view {
	Overview => scrolled("Overview scroll", overview(state, opened))
	Interactions => scrolled("Interactions scroll", interactions(state, opened))
	Spec => spec(state, opened)
	Health => scrolled("Health scroll", health(opened))
}

workspace : Observatory.State, Capture.Opened -> Gui.Elem(Observatory.State)
workspace = |state, opened| Gui.col(
	{ label: "Capture", width: Fill, height: Fill, grow: True, padding: 0, gap: 0 },
	[
		capture_bar(opened),
		banner(opened),
		Gui.row(
			{ label: "Workspace", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.paper },
			[nav(state), main_view(state, opened)],
		),
	],
)

render : Observatory.State -> Gui.Elem(Observatory.State)
render = |state| Gui.col(
	{ label: "Observatory", width: Fill, height: Fill, grow: True, padding: 0, gap: 0, bg: Theme.paper, fg: Theme.ink, font_size: Theme.body },
	[
		header(state),
		authority_bar(state),
		error_band(state),
		match state.capture {
			Some(opened) => workspace(state, opened)
			None => capture_list(state)
		},
	],
)
