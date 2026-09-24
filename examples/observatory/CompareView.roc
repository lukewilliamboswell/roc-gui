## Comparison as a mode (W8, US-31, US-32). The baseline bar sits under the
## capture bar on every view; the Compare view holds the comparability sheet
## and the A/A capture; and the Interactions and Memory tables take their Δ,
## ratio, and noise cells from here. An incomparable pair shows its reasons and
## no delta anywhere.
import pf.Gui
import Capture
import Compare
import Observatory
import Theme
import Widgets

Elem : Gui.Elem(Observatory.State)

CompareView := [].{
	## What every compared view draws from: the open capture, the baseline,
	## and the A/A capture, by the reading that produced each.
	same_comparison : Observatory.State, Observatory.State -> Bool
	same_comparison = |a, b| revisions(a) == revisions(b)

	## The comparison the open capture shows.
	mode : Observatory.State -> Compare.Mode
	mode = mode

	baseline_bar : Observatory.State -> Elem
	baseline_bar = baseline_bar

	compare : Observatory.State -> Elem
	compare = compare

	## The same comparison, and the same folder to choose an A/A capture from.
	same_view : Observatory.State, Observatory.State -> Bool
	same_view = |a, b| same_comparison(a, b) and folder_revision(a) == folder_revision(b)

	## The triggers table's extra headings and cells while a baseline applies.
	trigger_heads : Observatory.State -> List(Elem)
	trigger_heads = trigger_heads

	trigger_cells : Compare.Mode, Capture.Opened, Capture.Trigger -> List(Elem)
	trigger_cells = |current, opened, trigger| delta_cells("${trigger.trigger} ${trigger.patch_kind}", Compare.trigger_delta(current, opened, trigger), Compare.signed_ms)

	## The triggers table's order. |Δ| orders it only while deltas are shown;
	## otherwise it falls back to the median, so no table claims an order by a
	## column it does not show.
	trigger_sort : Observatory.State -> Observatory.Sort
	trigger_sort = |state| match mode(state) {
		On(_) => state.trigger_sort
		_ => if state.trigger_sort.column == Observatory.delta_column { column: 4, descending: True } else state.trigger_sort
	}

	## A cycle against its trigger group's median in the baseline.
	cycle_line : Compare.Mode, Capture.Opened, Capture.Cycle -> List(Elem)
	cycle_line = cycle_line

	allocation_heads : Compare.Mode -> List(Elem)
	allocation_heads = |current| match current {
		On(_) => [Widgets.head_figure("Δ bytes x̄", 100), Widgets.head_figure("ratio", 70), Widgets.head_cell("noise", 110)]
		_ => []
	}

	allocation_cells : Compare.Mode, Capture.Opened, Capture.TriggerAlloc -> List(Elem)
	allocation_cells = |current, opened, row| delta_cells("${row.trigger} ${row.span}", Compare.allocation_delta(current, opened, row), Compare.signed_bytes)
}

revisions : Observatory.State -> { capture : [None, Some(U64)], baseline : [None, Some(U64)], noise : [None, Some(U64)] }
revisions = |state| {
	capture: match state.capture {
		Some(opened) => Some(opened.revision)
		None => None
	},
	baseline: match state.baseline {
		Some(opened) => Some(opened.revision)
		None => None
	},
	noise: match state.noise {
		Some(member) => Some(member.opened.revision)
		None => None
	},
}

folder_revision : Observatory.State -> [None, Some(U64)]
folder_revision = |state| match state.folder {
	Some(found) => Some(found.revision)
	None => None
}

noise_opened : Observatory.State -> [None, Some(Capture.Opened)]
noise_opened = |state| match state.noise {
	Some(member) => Some(member.opened)
	None => None
}

mode : Observatory.State -> Compare.Mode
mode = |state| Compare.mode(state.capture, state.baseline, noise_opened(state))

## The baseline bar (US-32)

baseline_bar : Observatory.State -> Elem
baseline_bar = |state| {
	set = Widgets.key({ caption: "Set as baseline", label: "Set as baseline", selected: False, on_press: |current, _| Observatory.ask(current, SetBaseline) })
	clear = Widgets.key({ caption: "Clear", label: "Clear baseline", selected: False, on_press: |current, _| Observatory.ask(current, ClearBaseline) })
	name = |opened| Gui.row({ padding: 0, gap: 0, fg: Theme.ink, font_size: Theme.body, font_face: Theme.face, max_width: Px(260), text_overflow: Ellipsis }, [Gui.text("◆ ${opened.name}")])
	parts = match (state.baseline, mode(state)) {
		(None, _) => [Widgets.meta("BASELINE"), Widgets.labelled_note("Baseline verdict", "none: deltas appear once a baseline is set", Theme.dim)]
		(Some(base), Refused(refused)) => [
			Widgets.meta("BASELINE"),
			name(base),
			Widgets.labelled_note("Baseline verdict", "✗ incomparable: ${Str.join_with(refused.reasons, "; ")}. No deltas are shown.", Theme.alarm_ink),
		]
		(Some(base), On(applied)) => {
			noise = match (applied.noise, applied.noise_refused) {
				(Some(twin), _) => " · A/A ${twin.name}"
				(None, Some(reason)) => " · A/A refused: ${reason}"
				(None, None) => " · no A/A bound"
			}
			[Widgets.meta("BASELINE"), name(base), Widgets.labelled_note("Baseline verdict", "✓ comparable: Δ against the baseline${noise}", Theme.good)]
		}
		(Some(base), Off) => [Widgets.meta("BASELINE"), name(base)]
	}
	controls = match state.baseline {
		Some(_) => [set, clear]
		None => [set]
	}
	Gui.row(
		{ label: "Baseline bar", width: Fill, padding: Theme.inset, gap: Theme.inset, align: Center, bg: Theme.paper, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
		parts.append(Gui.row({ padding: 0, gap: 6, grow: True, justify: End }, controls)),
	)
}

## The comparability sheet (US-31)

sheet_row : Compare.Check -> Elem
sheet_row = |found| Widgets.labelled_row(
	"Gate ${found.key}",
	[
		Widgets.cell(found.key, 200, Theme.ink),
		Widgets.cell(found.a, 260, Theme.ink),
		Widgets.cell(found.b, 260, Theme.ink),
		Widgets.cell(Widgets.pass_mark(found.pass), 30, Widgets.pass_ink(found.pass)),
		Widgets.rest_cell(found.reason, Theme.alarm_ink),
	],
)

sheet : Capture.Opened, Capture.Opened -> List(Elem)
sheet = |base, opened| {
	checks = Compare.sheet(base, opened)
	failed = Compare.failures(checks)
	verdict = if failed.is_empty() {
		Widgets.labelled_note("Comparability verdict", "⇒ comparable: Interactions, the cycle inspector, and Memory show Δ against the baseline.", Theme.good)
	} else {
		Widgets.labelled_note("Comparability verdict", "⇒ incomparable: no deltas are shown. ${failed.len().to_str()} of ${checks.len().to_str()} keys fail.", Theme.alarm_ink)
	}
	[
		Widgets.heading("COMPARABILITY · A: ${base.name} ◆ baseline · B: ${opened.name}"),
		Widgets.note(Compare.rule),
		Widgets.table(
			"Comparability",
			[Widgets.table_head("Comparability columns", [Widgets.head_cell("key", 200), Widgets.head_cell("A", 260), Widgets.head_cell("B", 260), Widgets.head_cell("", 30), Widgets.head_rest("reason")])].concat(checks.map(sheet_row)),
		),
		verdict,
	]
}

## The A/A capture (US-32)

noise_row : Observatory.State, Capture.Listing -> Elem
noise_row = |state, listing| {
	chosen = match state.noise {
		Some(member) => member.opened.name == listing.name
		None => False
	}
	Widgets.labelled_row(
		"A/A row ${listing.name}",
		[
			Widgets.cell(listing.name, 260, Theme.ink),
			Widgets.cell(listing.spec, 240, Theme.dim),
			Widgets.figure_cell(listing.scale, 70, Theme.ink),
			Widgets.holder(
				140,
				[
					Widgets.row_key({
						caption: if chosen "✓ A/A" else "Use as A/A",
						label: "Use ${listing.name} as A/A",
						selected: chosen,
						on_press: |current, _| Observatory.ask(current, if chosen ClearNoise else ChooseNoise(listing.name)),
					}),
				],
			),
			Widgets.rest_cell("", Theme.dim),
		],
	)
}

noise_section : Observatory.State -> List(Elem)
noise_section = |state| {
	status = match mode(state) {
		On(applied) => match (applied.noise, applied.noise_refused) {
			(Some(twin), _) => Widgets.labelled_note("A/A verdict", "✓ ${twin.name} bounds every Δ: a Δ no larger than the A/A spread of the same value is within noise.", Theme.good)
			(None, Some(reason)) => Widgets.labelled_note("A/A verdict", "✗ refused: ${reason}", Theme.alarm_ink)
			(None, None) => Widgets.labelled_note("A/A verdict", "No A/A capture: deltas are shown without a noise bound.", Theme.dim)
		}
		_ => Widgets.labelled_note("A/A verdict", "An A/A capture bounds the deltas of a comparable baseline.", Theme.dim)
	}
	chooser = match state.folder {
		None => [Widgets.note("Open a folder of captures to choose an A/A capture from it.")]
		Some(folder) => [
			Gui.col(
				{ label: "A/A table", width: Fill, height: Px(Theme.row_height * 8), padding: 0, gap: 0, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
				[
					Widgets.table_head("A/A columns", [Widgets.head_cell("file", 260), Widgets.head_cell("spec", 240), Widgets.head_figure("scale", 70), Widgets.head_cell("", 140), Widgets.head_rest("")]),
					Gui.virtual_rows({
						label: "A/A captures",
						row_height: Theme.row_height,
						count: folder.captures.len(),
						render_row: |index| match folder.captures.get(index) {
							Ok(listing) => noise_row(state, listing)
							Err(_) => Widgets.labelled_row("", [])
						},
					}),
				],
			),
		]
	}
	[Widgets.heading("A/A NOISE"), Widgets.note(Compare.noise_rule), status].concat(chooser)
}

compare : Observatory.State -> Elem
compare = |state| {
	body = match (state.baseline, state.capture) {
		(Some(base), Some(opened)) => sheet(base, opened)
		_ => [
			Widgets.heading("COMPARABILITY"),
			Widgets.labelled_note("Comparability verdict", "No baseline. Open a capture and press Set as baseline, then open the capture to compare with it.", Theme.dim),
		]
	}
	Gui.col({ label: "Compare", width: Fill, padding: Theme.inset, gap: 6 }, body.concat(noise_section(state)))
}

## Δ cells

trigger_heads : Observatory.State -> List(Elem)
trigger_heads = |state| match mode(state) {
	On(_) => {
		active = state.trigger_sort.column == Observatory.delta_column
		arrow = if !active "" else if state.trigger_sort.descending " ▾" else " ▴"
		[
			Widgets.holder(
				110,
				[
					Gui.button({
						caption: "Δ median${arrow}",
						label: "Sort triggers by delta",
						on_press: |current, _| Gui.Action.update(Observatory.sort_triggers(current, Observatory.delta_column)),
						padding: 0,
						font_size: Theme.meta,
						font_face: Theme.face,
						radius: Theme.radius,
						bg: Theme.rail,
						hover_bg: Theme.quiet_hover,
						active_bg: Theme.quiet_active,
						fg: if active Theme.ink else Theme.dim,
						border_width: 0,
					}),
				],
			),
			Widgets.head_figure("ratio", 70),
			Widgets.head_cell("noise", 110),
		]
	}
	_ => []
}

noise_caption : Compare.Delta -> { text : Str, ink : Gui.Color }
noise_caption = |found| match Compare.within_noise(found) {
	Some(True) => { text: "within noise", ink: Theme.dim }
	Some(False) => { text: "beyond noise", ink: Theme.caution }
	None => { text: "no A/A bound", ink: Theme.dim }
}

## A row's Δ, ratio, and noise cells. The noise cell is named for its row,
## so a specification can find it whichever way the noise falls.
delta_cells : Str, [Hidden, Absent(Str), Shown(Compare.Delta)], (I64 -> Str) -> List(Elem)
delta_cells = |name, found, shape| match found {
	Hidden => []
	Absent(reason) => [Widgets.figure_cell("—", 110, Theme.ink), Widgets.figure_cell("—", 70, Theme.ink), Widgets.labelled_cell("Noise ${name}", reason, 110, Theme.dim)]
	Shown(delta) => {
		noise = noise_caption(delta)
		[Widgets.figure_cell(shape(delta.delta), 110, Theme.ink), Widgets.figure_cell(Compare.ratio(delta.value, delta.base), 70, Theme.ink), Widgets.labelled_cell("Noise ${name}", noise.text, 110, noise.ink)]
	}
}

cycle_line : Compare.Mode, Capture.Opened, Capture.Cycle -> List(Elem)
cycle_line = |current, opened, cycle| match Compare.cycle_delta(current, opened, cycle) {
	Hidden => []
	Absent(reason) => [Widgets.labelled_note("Baseline delta", "vs baseline: — (${reason})", Theme.dim)]
	Shown(delta) => {
		noise = noise_caption(delta)
		[Widgets.labelled_note("Baseline delta", "vs baseline median ${Compare.signed_ms(delta.delta)} · ${Compare.ratio(delta.value, delta.base)} · ${noise.text}", Theme.ink)]
	}
}
