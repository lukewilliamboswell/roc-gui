## Copy for review (US-37). A table's Copy button puts the rows it shows on
## the clipboard as Markdown, each with the evidence behind its values: the
## measurement family they come from, that family's status, and its reason, so
## a pasted `—` still says why. The table is built when the button is pressed,
## from the same rows the view drew.
import pf.Gui
import Capture
import Format
import Markdown
import Observatory
import Theme
import Widgets

Elem : Gui.Elem(Observatory.State)

## A table as text: its column names and its rows.
Table : { header : List(Str), rows : List(List(Str)) }

CopyView := [].{
	Table : Table

	## A section heading with the button that copies its table beside it, where
	## a table wider than the view cannot push it out of reach.
	heading : Str, Str, ({} -> Table) -> Elem
	heading = |caption, name, build| Gui.row(
		{ label: "Heading ${name}", width: Fill, padding: 0, padding_top: Px(Theme.inset), gap: Theme.inset, align: Center },
		[
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(caption)]),
			Widgets.row_key({ caption: "Copy", label: "Copy ${name}", selected: False, on_press: |current, _| copy(current, name, build({})) }),
		],
	)

	## The button alone, for a heading that holds other controls.
	copy_key : Str, ({} -> Table) -> Elem
	copy_key = |name, build| Widgets.row_key({ caption: "Copy", label: "Copy ${name}", selected: False, on_press: |current, _| copy(current, name, build({})) })

	## The triggers table's rows, as drawn.
	triggers : Capture.Opened, List(Capture.Trigger) -> Table
	triggers = |opened, rows| {
		timed = Capture.complete(opened, "host_cycles")
		shown = |ns| if timed Format.ms(ns) else "—"
		{
			header: ["trigger", "patch", "cycles", "min", "median", "max", "IQR"].concat(evidence_header),
			rows: rows.map(|found| [found.trigger, found.patch_kind, if timed found.count.to_str() else "—", shown(found.min), shown(found.median), shown(found.max), shown(found.iqr)].concat(evidence(opened, "host_cycles"))),
		}
	}

	## The cycles the list holds, slowest first.
	cycles : Capture.Opened, List(Capture.Cycle) -> Table
	cycles = |opened, rows| {
		timed = Capture.complete(opened, "host_cycles")
		shown = |ns| if timed Format.ms(ns) else "—"
		{
			header: ["cycle", "trigger", "patch", "phase", "duration", "callback", "validate", "apply"].concat(evidence_header),
			rows: rows.map(|cycle| ["r${cycle.run_id.to_str()} #${cycle.ordinal.to_str()}", cycle.trigger, cycle.patch_kind, cycle.phase, shown(cycle.duration), shown(cycle.callback), shown(cycle.validate), shown(cycle.apply)].concat(evidence(opened, "host_cycles"))),
		}
	}

	## A cycle's waterfall: every part, and the family each part comes from.
	waterfall : Capture.Opened, Capture.Inspected, [Shown, Absent(Str)] -> Table
	waterfall = waterfall

	## Allocations inside each span over each trigger's cycles.
	allocations : Capture.Opened, List(Capture.TriggerAlloc) -> Table
	allocations = |opened, rows| {
		present = Capture.complete(opened, "roc_work_spans")
		shown = |text| if present text else "—"
		{
			header: ["trigger", "span", "cycles", "calls mean", "calls max", "calls total", "bytes mean", "bytes max", "bytes total"].concat(evidence_header),
			rows: rows.map(
				|found| [found.trigger, found.span]
					.concat([found.cycles.to_str(), found.calls_mean.to_str(), found.calls_max.to_str(), found.calls_total.to_str(), Format.bytes(found.bytes_mean), Format.bytes(found.bytes_max), Format.bytes(found.bytes_total)].map(shown))
					.concat(evidence(opened, "roc_work_spans")),
			),
		}
	}

	## The steps the list holds, with each result.
	steps : Capture.Opened, List(Capture.Step), (Capture.Step -> Str) -> Table
	steps = |opened, rows, result| {
		timed = Capture.complete(opened, "step_results")
		{
			header: ["run", "ordinal", "line", "kind", "role", "status", "duration", "expected / observed · diagnostic"].concat(evidence_header),
			rows: rows.map(|step| [step.run_id.to_str(), step.ordinal.to_str(), step.line.to_str(), step.kind, step.role, step.status, if timed Format.maybe_ms(step.duration) else "—", result(step)].concat(evidence(opened, "step_results"))),
		}
	}

	## Every measurement family. Its own status and reason are its evidence.
	families : Capture.Opened -> Table
	families = |opened| {
		header: ["family", "detail", "status", "rows", "omitted", "reason"],
		rows: opened.families.map(|found| [found.name, found.detail, found.status, found.rows.to_str(), found.omitted.to_str(), found.reason]),
	}
}

evidence_header : List(Str)
evidence_header = ["family", "status", "reason"]

## The family behind a row's values, its status, and its reason.
evidence : Capture.Opened, Str -> List(Str)
evidence = |opened, name| match Capture.family(opened, name) {
	Found(found) => [found.name, found.status, found.reason]
	Missing => [name, "missing", "this capture has no row for the family"]
}

## Ask the root to put a table on the clipboard.
copy : Observatory.State, Str, Table -> Gui.Action(Observatory.State)
copy = |current, name, table| Observatory.ask(current, Copy({ name, rows: table.rows.len(), markdown: Markdown.table(name, table.header, table.rows) }))

waterfall : Capture.Opened, Capture.Inspected, [Shown, Absent(Str)] -> Table
waterfall = |opened, inspected, spans| {
	cycle = inspected.cycle
	parts = Capture.decompose(inspected)
	part : Str, Str, Str -> List(Str)
	part = |name, value, family| [name, value].concat(evidence(opened, family))
	absent : Str, Str, Str -> List(Str)
	absent = |name, family, reason| [name, "—", family, status_of(opened, family), reason]
	span_rows = match spans {
		Absent(reason) => [absent("spans", "roc_work_spans", reason)]
		Shown => Capture.span_kinds
			.map(
				|kind| match Capture.span(inspected, kind) {
					Found(found) => part(kind, Format.ms(found.duration), "roc_work_spans")
					Missing => part(kind, Format.ms(0), "roc_work_spans")
				},
			)
			.append(part("unattributed callback", Format.ms(parts.callback_rest), "roc_work_spans"))
	}
	gpui_rows = match inspected.gpui_apply {
		Some(gpui) => [
			part("gpui apply", Format.ms(gpui), "gpui_application"),
			match parts.apply_rest {
				Some(rest) => part("unattributed apply", Format.ms(rest), "gpui_application")
				None => absent("unattributed apply", "gpui_application", Capture.absence(opened, "gpui_application"))
			},
		]
		None => [absent("gpui apply", "gpui_application", Capture.absence(opened, "gpui_application"))]
	}
	{
		header: ["part", "duration"].concat(evidence_header),
		rows: [part("cycle", Format.ms(cycle.duration), "host_cycles"), part("roc callback", Format.ms(cycle.callback), "host_cycles")]
			.concat(span_rows)
			.concat([part("validate", Format.ms(cycle.validate), "host_cycles"), part("apply", Format.ms(cycle.apply), "host_cycles"), part("graph apply", Format.ms(inspected.graph_apply), "host_cycles")])
			.concat(gpui_rows)
			.append(part("unattributed cycle", Format.ms(parts.cycle_rest), "host_cycles")),
	}
}

status_of : Capture.Opened, Str -> Str
status_of = |opened, name| match Capture.family(opened, name) {
	Found(found) => found.status
	Missing => "missing"
}
