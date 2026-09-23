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
	same_view = |a, b| inputs(a) == inputs(b)

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

## The chart. Each trigger and metric is a group of bars, one per scale, each
## the member's mean against the largest mean of the group. This is the hook
## for the log-log canvas chart (P6): it takes the same members and rows, and
## a canvas with text replaces the bars without changing anything above it.
chart : List(Scaling.Member), List(Scaling.Row) -> List(Elem)
chart = |members, rows| {
	sorted = Scaling.ordered(members)
	bar_span = 320
	group = |row| {
		values = sorted.map(|member| { member, value: Scaling.value(member, row.trigger, row.metric) })
		largest = values.fold(0, |most, found| match found.value {
			Some(number) if number > most => number
			_ => most
		})
		values.map(
			|found| {
				scale_text = Capture.metadata(found.member.opened, "benchmark_scale")
				Gui.row(
					{ label: "Chart ${row.trigger} ${Scaling.metric_name(row.metric)} ${scale_text}", width: Fill, height: Px(18), padding: 0, gap: Theme.inset, align: Center },
					[
						Widgets.cell("${row.trigger} ${Scaling.metric_name(row.metric)}", 280, Theme.dim),
						Widgets.figure_cell(scale_text, 70, Theme.dim),
						match found.value {
							Some(number) => Gui.row({ width: Px(bar_span), padding: 0, gap: 0, align: Center }, [Widgets.block(if largest <= 0 or number <= 0 0 else (if number * bar_span.to_i64() / largest < 1 1 else (number * bar_span.to_i64() / largest).to_u32_wrap()), Theme.callback)])
							None => Gui.row({ width: Px(bar_span), padding: 0, gap: 0, align: Center }, [Widgets.meta("—")])
						},
						Widgets.figure_cell(
							match found.value {
								Some(number) => shape(row.metric, number)
								None => "—"
							},
							110,
							Theme.ink,
						),
					],
				)
			},
		)
	}
	[
		Widgets.heading("SCALING CHART · mean per measured sample cycle by scale, each bar against the largest of its group"),
		Gui.col({ label: "Scaling chart", width: Fill, padding: Theme.inset, gap: 2, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius }, rows.fold([], |drawn, row| drawn.concat(group(row)))),
	]
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
					.concat(chart(members, rows))
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
