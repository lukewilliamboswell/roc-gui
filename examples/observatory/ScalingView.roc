## Scaling (W7, US-29, US-30): choose captures of one executable at several
## scales from the folder, see the gate that admits or refuses them, the scale
## checks each recorded, and how every trigger's work grows from scale to
## scale, with an A/A capture's band marking the ratios that are noise.
import pf.Gui
import Capture
import Compare
import Format
import Observatory
import Scaling
import Theme
import Widgets

Elem : Gui.Elem(Observatory.State)

ScalingView := [].{
	## The folder to choose from, the set as chosen and as read, and the A/A
	## capture.
	same_view : Observatory.State, Observatory.State -> Bool
	same_view = |a, b| inputs(a) == inputs(b) and a.chart_width == b.chart_width

	scaling : Observatory.State -> Elem
	scaling = scaling
}

inputs : Observatory.State -> { folder : [None, Some(U64)], chosen : List(Str), read : U64, noise : [None, Some(U64)] }
inputs = |state| {
	folder: match state.folder {
		Some(found) => Some(found.revision)
		None => None
	},
	chosen: state.scaling.chosen,
	read: state.scaling.read,
	noise: match state.noise {
		Some(member) => Some(member.opened.revision)
		None => None
	},
}

## Choosing the set

choice_row : Observatory.State, Capture.Listing -> Elem
choice_row = |state, listing| {
	chosen = state.scaling.chosen.contains(listing.name)
	aa = match state.noise {
		Some(member) => member.opened.name == listing.name
		None => False
	}
	Widgets.labelled_row(
		"Scaling row ${listing.name}",
		[
			Widgets.cell(listing.name, 240, Theme.ink),
			Widgets.cell(listing.application, 150, Theme.dim),
			Widgets.cell(listing.spec, 220, Theme.dim),
			Widgets.figure_cell(listing.scale, 70, Theme.ink),
			Widgets.holder(
				110,
				[
					Widgets.row_key({
						caption: if chosen "✓ in set" else "Add to set",
						label: "Scaling set ${listing.name}",
						selected: chosen,
						on_press: |current, _| Gui.update(Observatory.toggle_scaling(current, listing.name)),
					}),
				],
			),
			Widgets.holder(
				110,
				[
					Widgets.row_key({
						caption: if aa "✓ A/A" else "Use as A/A",
						label: "Scaling A/A ${listing.name}",
						selected: aa,
						on_press: |current, _| Observatory.ask(current, if aa ClearNoise else ChooseNoise(listing.name)),
					}),
				],
			),
			Widgets.rest_cell("", Theme.dim),
		],
	)
}

chooser : Observatory.State -> List(Elem)
chooser = |state| match state.folder {
	None => [Widgets.labelled_note("Scaling verdict", "Open a folder of captures to choose a scaling set from it.", Theme.dim)]
	Some(folder) => {
		chosen = state.scaling.chosen
		[
			Gui.row(
				{ width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[
					Widgets.meta("CHOSEN ${chosen.len().to_str()}: ${if chosen.is_empty() "none" else Str.join_with(chosen, " · ")}"),
					Gui.row(
						{ padding: 0, gap: 0, grow: True, justify: End },
						[Widgets.key({ caption: "Build scaling set", label: "Build scaling set", selected: False, on_press: |current, _| Observatory.ask(current, BuildScaling) })],
					),
				],
			),
			Gui.col(
				{ label: "Scaling choices", width: Fill, height: Px(Theme.row_height * 8), padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
				[
					Widgets.table_head("Scaling choice columns", [Widgets.head_cell("file", 240), Widgets.head_cell("app", 150), Widgets.head_cell("spec", 220), Widgets.head_figure("scale", 70), Widgets.head_cell("set", 110), Widgets.head_cell("A/A", 110), Widgets.head_rest("")]),
					Gui.virtual_rows({
						label: "Scaling captures",
						row_height: Theme.row_height,
						count: folder.captures.len(),
						render_row: |index| match folder.captures.get(index) {
							Ok(listing) => choice_row(state, listing)
							Err(_) => Widgets.labelled_row("", [])
						},
					}),
				],
			),
		]
	}
}

## The gate

gate_row : Scaling.Gate -> Elem
gate_row = |found| Widgets.labelled_row(
	"Scaling gate ${found.key}",
	[Widgets.cell(found.key, 180, Theme.ink), Widgets.cell(Widgets.pass_mark(found.pass), 30, Widgets.pass_ink(found.pass)), Widgets.rest_cell(found.detail, Theme.alarm_ink)],
)

gate_table : List(Scaling.Gate) -> Elem
gate_table = |checks| Widgets.table(
	"Scaling gate",
	[Widgets.table_head("Scaling gate columns", [Widgets.head_cell("key", 180), Widgets.head_cell("", 30), Widgets.head_rest("failing capture")])].concat(checks.map(gate_row)),
)

## Scale verification: the count assertions every capture of the set made.
checks_table : List(Scaling.Member) -> List(Elem)
checks_table = |members| {
	row = |member| {
		present = Capture.complete(member.opened, "scale_verification")
		held = member.checks.mismatches == 0 and member.checks.checks > 0
		Widgets.labelled_row(
			"Scale check ${member.opened.name}",
			if present {
				[
					Widgets.cell(member.opened.name, 240, Theme.ink),
					Widgets.figure_cell(Capture.metadata(member.opened, "benchmark_scale"), 80, Theme.ink),
					Widgets.figure_cell(member.checks.checks.to_str(), 70, Theme.ink),
					Widgets.figure_cell(member.checks.mismatches.to_str(), 90, Theme.ink),
					Widgets.cell(Widgets.pass_mark(held), 30, Widgets.pass_ink(held)),
					Widgets.rest_cell("", Theme.dim),
				]
			} else {
				[
					Widgets.cell(member.opened.name, 240, Theme.ink),
					Widgets.figure_cell(Capture.metadata(member.opened, "benchmark_scale"), 80, Theme.ink),
					Widgets.figure_cell("—", 70, Theme.ink),
					Widgets.figure_cell("—", 90, Theme.ink),
					Widgets.cell("", 30, Theme.dim),
					Widgets.rest_cell(Capture.absence(member.opened, "scale_verification"), Theme.dim),
				]
			},
		)
	}
	[
		Widgets.heading("SCALE VERIFICATION · count assertions of every run but warmups"),
		Widgets.table(
			"Scale checks",
			[Widgets.table_head("Scale check columns", [Widgets.head_cell("capture", 240), Widgets.head_figure("scale", 80), Widgets.head_figure("checks", 70), Widgets.head_figure("mismatches", 90), Widgets.head_cell("", 30), Widgets.head_rest("")])].concat(members.map(row)),
		),
	]
}

## The A/A capture, accepted against the member of its own scale.
noise_for : Observatory.State, List(Scaling.Member) -> { applied : [None, Some(Scaling.Member)], text : Str, ink : Gui.Color }
noise_for = |state, members| match state.noise {
	None => { applied: None, text: "No A/A capture: ratios carry no noise band.", ink: Theme.dim }
	Some(twin) => match members.find_first(|member| Scaling.scale(member) == Scaling.scale(twin)) {
		Err(_) => { applied: None, text: "✗ A/A ${twin.opened.name} refused: benchmark_scale: no capture of the set has scale ${Capture.metadata(twin.opened, "benchmark_scale")}", ink: Theme.alarm_ink }
		Ok(member) => match Compare.accept_noise(member.opened, twin.opened) {
			Ok({}) => { applied: Some(twin), text: "✓ A/A ${twin.opened.name} bounds the set against ${member.opened.name}", ink: Theme.good }
			Err(reason) => { applied: None, text: "✗ A/A ${twin.opened.name} refused: ${reason}", ink: Theme.alarm_ink }
		}
	}
}

## Ratios

shape : Scaling.Metric, I64 -> Str
shape = |metric, value| match metric {
	Allocated => Format.bytes(value)
	_ => Format.ms(value)
}

step_text : Scaling.Step -> Str
step_text = |step| match step.observed {
	None => "—"
	Some(fraction) => match step.noise {
		Some(True) => "${Scaling.ratio_text(fraction)} within noise"
		Some(False) => "${Scaling.ratio_text(fraction)} beyond noise"
		None => Scaling.ratio_text(fraction)
	}
}

step_width : U32
step_width = 190

ratio_row : Scaling.Row -> Elem
ratio_row = |row| {
	name = Scaling.metric_name(row.metric)
	Widgets.labelled_row(
		"Ratio ${row.trigger} ${name}",
		[Widgets.cell(row.trigger, 110, Theme.ink), Widgets.cell(name, 170, Theme.dim)]
			.concat(row.steps.map(|step| Widgets.figure_cell(step_text(step), step_width, Theme.ink)))
			.concat(
				match row.verdict {
					Some(verdict) => [Widgets.cell(verdict, 120, if verdict == "super-linear" Theme.alarm_ink else Theme.ink), Widgets.rest_cell("", Theme.dim)]
					None => [Widgets.cell("—", 120, Theme.ink), Widgets.rest_cell(row.absence, Theme.dim)]
				},
			),
	)
}

ratios_table : List(Scaling.Member), List(Scaling.Row) -> List(Elem)
ratios_table = |members, rows| {
	sorted = Scaling.ordered(members)
	scales = sorted.map(|member| Scaling.scale(member))
	step_heads = List.map2(
		scales.drop_last(1),
		scales.drop_first(1),
		|a, b| match (a, b) {
			(Some(low), Some(high)) => Widgets.head_figure("${low.to_str()}→${high.to_str()} (${Scaling.ratio_text({ num: high, den: low })})", step_width)
			_ => Widgets.head_figure("", step_width)
		},
	)
	[
		Widgets.heading("SCALING RATIOS · observed ratio of the mean per measured sample cycle, against the scale ratio"),
		Widgets.note(Scaling.verdict_rule),
		Widgets.table(
			"Scaling ratios",
			[Widgets.table_head("Scaling ratio columns", [Widgets.head_cell("trigger", 110), Widgets.head_cell("metric", 170)].concat(step_heads).concat([Widgets.head_cell("verdict", 120), Widgets.head_rest("")]))].concat(rows.map(ratio_row)),
		),
	]
}

## The chart: for each trigger and metric, a log-log canvas of the member's
## mean against its scale, one point per scale joined in scale order, with a
## dashed reference line of slope one through the smallest scale's point, so
## linear growth runs along the reference and anything steeper rises above it.
chart : Observatory.State, List(Scaling.Member), List(Scaling.Row) -> List(Elem)
chart = |state, members, rows| {
	sorted = Scaling.ordered(members)
	plot_width = plot_width_of(state)
	plotted = rows.map(|row| plot(sorted, row, plot_width))
	[Widgets.heading("SCALING CHART · mean per measured sample cycle against scale, log-log · dashed: linear growth from the smallest scale")].concat(plotted)
}

## Hundredths of a base-two logarithm, exact at powers of two and linear
## between them, so equal ratios are equal distances.
log_hundredths : I64 -> I64
log_hundredths = |value| if value <= 1 {
	0
} else {
	var $power = 1
	var $octaves = 0
	while $power * 2 <= value {
		$power = $power * 2
		$octaves = $octaves + 1
	}
	$octaves * 100 + (value - $power) * 100 / $power
}

expect log_hundredths(1024) == 1000
expect log_hundredths(1536) == 1050

plot_left : I64
plot_left = 64

## The plot's width: what the window laid the chart out at, less the axis on
## its left and the captions on its right, and never narrower than a readable
## plot. Before the window has laid the chart out it is drawn at the width it
## had below a view.
plot_width_of : Observatory.State -> I64
plot_width_of = |state| if state.chart_width == 0 {
	360
} else {
	laid_out = state.chart_width.to_i64() - plot_left - 108
	if laid_out < least_plot least_plot else laid_out
}

least_plot : I64
least_plot = 240

plot_top : I64
plot_top = 18

plot_height : I64
plot_height = 100

## A position along one axis of `span` pixels, from `low` to `high` hundredths.
along : I64, I64, I64, I64 -> I64
along = |value, low, high, span| if high <= low span / 2 else (value - low) * span / (high - low)

plot : List(Scaling.Member), Scaling.Row, I64 -> Elem
plot = |sorted, row, plot_width| {
	name = "${row.trigger} ${Scaling.metric_name(row.metric)}"
	points = sorted.keep_oks(
		|member| match (Scaling.scale(member), Scaling.value(member, row.trigger, row.metric)) {
			(Some(scale), Some(value)) if scale > 0 and value > 0 => Ok({ scale, value, x: log_hundredths(scale), y: log_hundredths(value) })
			_ => Err(Absent)
		},
	)
	low_x = points.fold(1000000, |least, found| if found.x < least found.x else least)
	high_x = points.fold(0, |most, found| if found.x > most found.x else most)
	first_y = match points.first() {
		Ok(found) => found.y
		Err(_) => 0
	}
	# The reference line's far end, where linear growth from the first point
	# reaches the largest scale.
	reference_y = first_y + (high_x - low_x)
	low_y = points.fold(first_y, |least, found| if found.y < least found.y else least)
	high_y = points.fold(reference_y, |most, found| if found.y > most found.y else most)
	px_x = |value| plot_left + along(value, low_x, high_x, plot_width)
	px_y = |value| plot_top + plot_height - along(value, low_y, high_y, plot_height)
	dots = points.map_with_index(
		|found, index| Gui.ellipse({ key: (index + 1).to_u64_wrap(), label: "Point ${name} ${found.scale.to_str()}", x: (px_x(found.x) - 3).to_i32_wrap(), y: (px_y(found.y) - 3).to_i32_wrap(), width: 7, height: 7, fill: Theme.callback }),
	)
	joins = List.map2(points, points.drop_first(1), |from, to| { from, to }).map_with_index(
		|pair, index| Gui.line({ key: (100 + index).to_u64_wrap(), label: "Join ${name} ${index.to_str()}", x1: px_x(pair.from.x).to_i32_wrap(), y1: px_y(pair.from.y).to_i32_wrap(), x2: px_x(pair.to.x).to_i32_wrap(), y2: px_y(pair.to.y).to_i32_wrap(), stroke: Theme.callback, stroke_width: 2 }),
	)
	# A dashed line: short segments along the reference.
	dashes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(
		|segment| {
			from = low_x + (high_x - low_x) * segment * 2 / 24
			to = low_x + (high_x - low_x) * (segment * 2 + 1) / 24
			Gui.line({ key: (200 + segment).to_u64_wrap(), label: "Reference ${name} ${segment.to_str()}", x1: px_x(from).to_i32_wrap(), y1: px_y(first_y + from - low_x).to_i32_wrap(), x2: px_x(to).to_i32_wrap(), y2: px_y(first_y + to - low_x).to_i32_wrap(), stroke: Theme.edge, stroke_width: 1 })
		},
	)
	scale_captions = points.map_with_index(
		|found, index| Gui.canvas_text({ key: (300 + index).to_u64_wrap(), label: "Scale ${name} ${found.scale.to_str()}", x: (px_x(found.x) - 40).to_i32_wrap(), y: (plot_top + plot_height + 20).to_i32_wrap(), width: 80, value: found.scale.to_str(), color: Theme.dim, size: 10, align: Center }),
	)
	# A value reads on the side of its point away from the reference line,
	# below a point that grew no faster than linear and above one that grew
	# faster, so the dashes never strike through it. The scales sit below
	# the lowest value's caption.
	value_y = |found| {
		at = px_y(found.y)
		if at >= px_y(first_y + found.x - low_x) at + 4 else at - 14
	}
	value_captions = points.map_with_index(
		|found, index| Gui.canvas_text({ key: (400 + index).to_u64_wrap(), label: "Value ${name} ${found.scale.to_str()}", x: (px_x(found.x) + 6).to_i32_wrap(), y: value_y(found).to_i32_wrap(), width: 90, value: shape(row.metric, found.value), color: Theme.ink, size: 10, align: Start }),
	)
	title = Gui.canvas_text({ key: 500, label: "Title ${name}", x: 0, y: 0, width: (plot_left + plot_width).to_i32_wrap().to_u32_wrap(), value: name, color: Theme.dim, size: 11, align: Start })
	primitives = if points.len() < 2 {
		[title, Gui.canvas_text({ key: 501, label: "Absent ${name}", x: plot_left.to_i32_wrap(), y: 50, width: plot_width.to_u32_wrap(), value: "fewer than two scales have this value", color: Theme.dim, size: 11, align: Start })]
	} else {
		[title].concat(dashes).concat(joins).concat(dots).concat(scale_captions).concat(value_captions)
	}
	Gui.canvas({
		label: "Scaling chart ${name}",
		primitives,
		on_pointer: |_, _| Gui.none,
		on_size: Some(|current, laid_out| Observatory.size_charts(current, laid_out)),
		width: Fill,
		height: Px((plot_top + plot_height + 36).to_u32_wrap()),
		min_width: Px((plot_left + least_plot + 110).to_u32_wrap()),
		min_height: Px((plot_top + plot_height + 36).to_u32_wrap()),
		bg: Theme.card,
		border_color: Theme.line,
		border_width: 1,
		radius: Theme.radius,
	})
}

result : Observatory.State -> List(Elem)
result = |state| {
	members = state.scaling.members
	if members.is_empty() {
		[]
	} else if members.map(|member| member.opened.name) != state.scaling.chosen {
		# A set shown beside a different choice would describe captures that
		# are no longer chosen.
		[Widgets.labelled_note("Scaling verdict", "The chosen captures changed: press Build scaling set to read them.", Theme.dim)]
	} else {
		checks = Scaling.gate(members)
		match Scaling.refusal(checks) {
			Some(reason) => [
				Widgets.heading("GATE"),
				Widgets.labelled_note("Scaling verdict", "✗ refused: ${reason}", Theme.alarm_ink),
				gate_table(checks),
			]
			None => {
				noise = noise_for(state, members)
				rows = Scaling.rows(members, noise.applied)
				scales = Scaling.ordered(members).map(|member| Capture.metadata(member.opened, "benchmark_scale"))
				[
					Widgets.heading("GATE"),
					Widgets.labelled_note("Scaling verdict", "✓ ${members.len().to_str()} captures at scales ${Str.join_with(scales, " · ")}", Theme.good),
					gate_table(checks),
				]
					.concat(checks_table(Scaling.ordered(members)))
					.concat([Widgets.heading("A/A NOISE BAND"), Widgets.note(Scaling.noise_rule), Widgets.labelled_note("Scaling A/A verdict", noise.text, noise.ink)])
					.concat(ratios_table(members, rows))
					.concat(chart(state, members, rows))
			}
		}
	}
}

scaling : Observatory.State -> Elem
scaling = |state| Gui.col(
	{ label: "Scaling", width: Fill, padding: Theme.inset, gap: 6 },
	[Widgets.heading("SCALING SET"), Widgets.note(Scaling.rule)]
		.concat(chooser(state))
		.concat(result(state)),
)
