## Timeline (W6, US-26): what happened, in order. Lanes of cycles by trigger,
## drawn frames, and virtual-list passes share the capture's one clock. The
## wheel zooms around the instant under the pointer and pans sideways, hovering
## a mark reads it out, pressing a frame shows the cycles its owner recorded it
## was the first to draw, and pressing a cycle opens it in the inspector. A
## frame with no recorded link is marked "cause not recorded", never tied to
## the nearest cycle.
import pf.Gui
import Capture
import Format
import Observatory
import Theme
import Timeline
import Widgets

Elem : Gui.Elem(Observatory.State)

## What a hit target stands for.
Hit : [OnCycle(Timeline.CycleMark), OnFrame(Timeline.FrameMark), OnPass(Timeline.PassMark)]

TimelineView := [].{
	## The capture, the span read, and the frame pressed.
	same_view : Observatory.State, Observatory.State -> Bool
	same_view = |a, b| inputs(a) == inputs(b)

	timeline : Observatory.State, Capture.Opened -> Elem
	timeline = timeline

	## The pressed frame's detail, which the inspector shows beside the chart.
	detail : Elem
	detail = Gui.col(
		{ label: "Timeline frame", width: Fill, padding: Theme.inset, gap: 4, bg: Theme.card, border_color: Theme.line, border_width: 1, radius: Theme.radius },
		[part("Timeline frame detail", |a, b| inputs(a) == inputs(b), frame_panel)],
	)

	## The cycles a frame's owner recorded it was the first to draw, each of
	## which opens in the inspector, or why no cause is shown.
	causes : Capture.Opened, Capture.FrameDetail -> List(Elem)
	causes = causes
}

frame_of : Observatory.State -> [None, Some(I64)]
frame_of = |state| match state.frame {
	Some(detail) => Some(detail.id)
	None => None
}

inputs : Observatory.State -> { capture : [None, Some(U64)], read : U64, frame : [None, Some(I64)] }
inputs = |state| {
	capture: match state.capture {
		Some(opened) => Some(opened.revision)
		None => None
	},
	read: state.clock.read,
	frame: frame_of(state),
}

gutter : I64
gutter = 96

plot : I64
plot = 720

lanes_top : I64
lanes_top = 40

lane_height : I64
lane_height = 18

lane_pitch : I64
lane_pitch = 26

## Keys from 1 are hit targets; every other shape's key is offset past any
## number of them.
painted : I64, I64 -> U64
painted = |layer, index| (layer * 1000000 + index).to_u64_wrap()

box : { key : U64, label : Str, x : I64, y : I64, width : I64, height : I64, fill : Gui.Color } -> Gui.CanvasPrimitive
box = |props| Gui.rectangle({
	key: props.key,
	label: props.label,
	x: props.x.to_i32_wrap(),
	y: props.y.to_i32_wrap(),
	width: if props.width < 0 0 else props.width.to_u32_wrap(),
	height: if props.height < 0 0 else props.height.to_u32_wrap(),
	fill: props.fill,
})

rule : { key : U64, label : Str, x1 : I64, y1 : I64, x2 : I64, y2 : I64, stroke : Gui.Color } -> Gui.CanvasPrimitive
rule = |props| Gui.line({ key: props.key, label: props.label, x1: props.x1.to_i32_wrap(), y1: props.y1.to_i32_wrap(), x2: props.x2.to_i32_wrap(), y2: props.y2.to_i32_wrap(), stroke: props.stroke, stroke_width: 1 })

caption : { key : U64, label : Str, x : I64, y : I64, width : I64, value : Str, color : Gui.Color, align : Gui.CanvasTextAlign } -> Gui.CanvasPrimitive
caption = |props| Gui.canvas_text({
	key: props.key,
	label: props.label,
	x: props.x.to_i32_wrap(),
	y: props.y.to_i32_wrap(),
	width: props.width.to_u32_wrap(),
	value: props.value,
	color: props.color,
	size: 11,
	align: props.align,
})

lane_y : I64 -> I64
lane_y = |lane| lanes_top + lane * lane_pitch

## Where an interval falls on the plot: clipped to the window, and at least two
## pixels wide so an instant is still a mark.
extent : Timeline.Window, I64, I64 -> { x : I64, width : I64 }
extent = |window, start, end| {
	stop = window.start + window.span
	from = if start < window.start window.start else start
	to = if end > stop stop else end
	x = gutter + (from - window.start) * plot / window.span
	width = (to - from) * plot / window.span
	{ x, width: if width < 2 2 else width }
}

cycle_name : Capture.Cycle -> Str
cycle_name = |cycle| "r${cycle.run_id.to_str()} #${cycle.ordinal.to_str()}"

frame_name : Capture.Bar -> Str
frame_name = |bar| "r${bar.run_id.to_str()} #${bar.ordinal.to_str()}"

hit_name : Hit -> Str
hit_name = |hit| match hit {
	OnCycle(mark) => "Cycle ${cycle_name(mark.cycle)}"
	OnFrame(mark) => "Frame ${frame_name(mark.bar)}"
	OnPass(mark) => "List ${mark.list_id.to_str()} pass ${mark.column.to_str()}"
}

more : I64, Str -> Str
more = |count, noun| if count > 1 " · longest of ${count.to_str()} ${noun} here" else ""

## A pass names what produced it only through the key the recorder wrote.
pass_origin : Timeline.PassMark -> Str
pass_origin = |mark| match (mark.origin, mark.frame, mark.cycle) {
	("paint", Some(ordinal), _) => "painted by frame #${ordinal.to_str()}"
	("paint", None, _) => "paint pass, frame not recorded"
	(_, _, Some(ordinal)) => "patch of cycle #${ordinal.to_str()}"
	_ => "patch of no recorded cycle"
}

readout : Timeline.Window, Hit -> Str
readout = |window, hit| match hit {
	OnCycle(mark) => "cycle ${cycle_name(mark.cycle)} · ${mark.cycle.trigger} · ${Capture.target_caption(mark.cycle)} · ${mark.cycle.patch_kind} · ${Format.ms(mark.end - mark.start)} at ${Format.ms(mark.start - window.first)}${more(mark.cycles, "cycles")}"
	OnFrame(mark) => {
		drew = if mark.causes > 0 "first to draw ${mark.causes.to_str()} cycle(s)" else "cause not recorded"
		"frame ${frame_name(mark.bar)} · host stages ${Format.ms(mark.bar.layout + mark.bar.prepaint + mark.bar.paint)} · ${drew} at ${Format.ms(mark.start - window.first)}${more(mark.frames, "frames")}"
	}
	OnPass(mark) => "list ${mark.list_id.to_str()} · ${pass_origin(mark)} · visible ${mark.visible.to_str()} · materialised ${mark.materialized.to_str()} at ${Format.ms(mark.start - window.first)}${more(mark.passes, "passes")}"
}

hits_of : Timeline.Window -> List(Hit)
hits_of = |window| window.cycles.map(|mark| OnCycle(mark)).concat(window.frames.map(|mark| OnFrame(mark))).concat(window.passes.map(|mark| OnPass(mark)))

lane_of : Timeline.Window, Hit -> I64
lane_of = |window, hit| {
	triggers = window.triggers.len().to_i64_wrap()
	match hit {
		OnCycle(mark) => match window.triggers.find_first_index(|trigger| trigger == mark.cycle.trigger) {
			Ok(index) => index.to_i64_wrap()
			Err(_) => 0
		}
		OnFrame(_) => triggers
		OnPass(_) => triggers + 1
	}
}

hit_extent : Timeline.Window, Hit -> { x : I64, width : I64 }
hit_extent = |window, hit| match hit {
	OnCycle(mark) => extent(window, mark.start, mark.end)
	OnFrame(mark) => extent(window, mark.start, mark.end)
	OnPass(mark) => extent(window, mark.start, mark.end)
}

hit_color : Hit -> Gui.Color
hit_color = |hit| match hit {
	OnCycle(_) => Theme.callback
	OnFrame(mark) => if mark.causes > 0 Theme.span else Theme.validate
	OnPass(_) => Theme.unattributed
}

## A lane whose family was not recorded is a band that says so, never empty.
absent_band : Capture.Opened, I64, Str, Str -> List(Gui.CanvasPrimitive)
absent_band = |opened, lane, name, family_name| if Capture.complete(opened, family_name) {
	[]
} else {
	y = lane_y(lane)
	[
		box({ key: painted(3, lane), label: "Unavailable ${name}", x: gutter, y, width: plot, height: lane_height, fill: Theme.rail }),
		caption({ key: painted(4, lane), label: "Reason ${name}", x: gutter + 6, y: y + 3, width: plot - 12, value: Capture.absence(opened, family_name), color: Theme.dim, align: Start }),
	]
}

lane_caption : I64, Str -> Gui.CanvasPrimitive
lane_caption = |lane, name| caption({ key: painted(2, lane), label: "Lane ${name}", x: 0, y: lane_y(lane) + 3, width: gutter - 8, value: name, color: Theme.dim, align: End })

chart : Observatory.State, Capture.Opened -> List(Elem)
chart = |state, opened| {
	window = state.clock.window
	hits = hits_of(window)
	count = hits.len().to_i64_wrap()
	triggers = window.triggers.len().to_i64_wrap()
	lanes = triggers + 2
	bottom = lane_y(lanes)
	marks = hits.map_with_index(
		|hit, index| {
			place = hit_extent(window, hit)
			box({ key: (index + 1), label: hit_name(hit), x: place.x, y: lane_y(lane_of(window, hit)), width: place.width, height: lane_height, fill: hit_color(hit) })
		},
	)
	hovered = match state.clock_hover {
		Some(index) => match hits.get(index.to_u64_wrap()) {
			Ok(hit) => Some(hit)
			Err(_) => None
		}
		None => None
	}
	## A band across every lane, so what else happened at that instant lines
	## up with the hovered mark.
	highlight = match hovered {
		Some(hit) => {
			place = hit_extent(window, hit)
			[box({ key: painted(5, 1), label: "Hovered mark", x: place.x - 1, y: lanes_top - 2, width: place.width + 2, height: bottom - lanes_top, fill: Theme.selected })]
		}
		None => []
	}
	## The pressed frame and the cycles its owner linked to it, where the
	## window shows them.
	selected = match state.frame {
		Some(detail) => {
			frame = window.frames.keep_if(|mark| mark.bar.id == detail.id).map(
				|mark| {
					place = extent(window, mark.start, mark.end)
					rule({ key: painted(6, 1), label: "Selected frame", x1: place.x, y1: lanes_top - 4, x2: place.x, y2: bottom, stroke: Theme.alarm_ink })
				},
			)
			linked = window.cycles.keep_if(|mark| detail.causes.any(|cause| cause.id == mark.cycle.id)).map_with_index(
				|mark, index| {
					place = extent(window, mark.start, mark.end)
					y = lane_y(lane_of(window, OnCycle(mark))) + lane_height + 1
					rule({ key: painted(7, index.to_i64_wrap()), label: "Linked cycle ${cycle_name(mark.cycle)}", x1: place.x, y1: y, x2: place.x + place.width, y2: y, stroke: Theme.alarm_ink })
				},
			)
			frame.concat(linked)
		}
		None => []
	}
	readout_text = match hovered {
		Some(hit) => readout(window, hit)
		None => "Hover a mark for its detail; press a frame for the cycles it drew, or a cycle to inspect it; scroll to zoom."
	}
	stop = window.start + window.span
	guides = [
		caption({ key: painted(1, 1), label: "Timeline readout", x: gutter, y: 2, width: plot, value: readout_text, color: Theme.ink, align: Start }),
		caption({ key: painted(1, 2), label: "Window start", x: gutter, y: 20, width: plot / 2, value: Format.ms(window.start - window.first), color: Theme.dim, align: Start }),
		caption({ key: painted(1, 3), label: "Window end", x: gutter + plot / 2, y: 20, width: plot / 2, value: Format.ms(stop - window.first), color: Theme.dim, align: End }),
		rule({ key: painted(1, 4), label: "Clock axis", x1: gutter, y1: lanes_top - 4, x2: gutter + plot, y2: lanes_top - 4, stroke: Theme.edge }),
	]
	labels = window.triggers.map_with_index(|trigger, index| lane_caption(index.to_i64_wrap(), "cycles ${trigger}"))
		.append(lane_caption(triggers, "frames"))
		.append(lane_caption(triggers + 1, "lists"))
	bands = absent_band(opened, triggers, "frames", "gpui_frame_spans").concat(absent_band(opened, triggers + 1, "lists", "virtual_list_materialization"))
	hit_at : I64 -> [None, Some(Hit)]
	hit_at = |index| match hits.get(index.to_u64_wrap()) {
		Ok(hit) => Some(hit)
		Err(_) => None
	}
	target : [None, Some(U64)] -> [None, Some(I64)]
	target = |key| match key {
		Some(hit) if hit >= 1 and hit.to_i64_wrap() <= count => Some(hit.to_i64_wrap() - 1)
		_ => None
	}
	hit_of_target : [None, Some(U64)] -> [None, Some(Hit)]
	hit_of_target = |key| match target(key) {
		Some(index) => hit_at(index)
		None => None
	}
	width = gutter + plot + 8
	height = bottom + 4
	span_caption = if window.start == window.first and stop == window.last "the whole capture" else "${Format.ms(window.span)} of ${Format.ms(window.last - window.first)}"
	whole = if window.span < window.last - window.first [Widgets.key({ caption: "Whole capture", label: "Show the whole timeline", selected: False, on_press: |current, _| Observatory.ask(current, ShowTimeline(0, 0)) })] else []
	[
		Gui.row(
			{ label: "Timeline heading", width: Fill, padding: 0, gap: Theme.inset, align: Center },
			[Widgets.meta("TIMELINE · cycles by trigger · frames · list passes · ${span_caption} · one process-relative clock")].concat(whole),
		),
		Gui.canvas({
			label: "Timeline",
			primitives: highlight.concat(marks).concat(selected).concat(guides).concat(labels).concat(bands),
			## A frame is chosen as it is pressed, as in the strip. A cycle opens
			## another view, so it opens as the press ends, once the gesture that
			## began on this canvas is complete.
			on_pointer: |current, event| match (event.phase, hit_of_target(event.target)) {
				(Begin, Some(OnFrame(mark))) => Observatory.ask(current, SelectFrame(mark.bar))
				(End, Some(OnCycle(mark))) => Observatory.ask(current, InspectCycle(mark.cycle))
				_ => Gui.none
			},
			on_hover: Some(
				|current, event| {
					index = match event.phase {
						Move => target(event.target)
						Leave => None
					}
					if index == current.clock_hover Gui.none else Gui.update({ ..current, clock_hover: index })
				},
			),
			on_wheel: Some(
				|current, wheel| match Timeline.zoomed(current.clock.window, wheel.x.to_i64() - gutter, plot, wheel.dx, wheel.dy) {
					Some(next) => Observatory.ask(current, ShowTimeline(next.start, next.span))
					None => Gui.none
				},
			),
			width: Px(width.to_u32_wrap()),
			height: Px(height.to_u32_wrap()),
			min_width: Px(width.to_u32_wrap()),
			min_height: Px(height.to_u32_wrap()),
			bg: Theme.card,
			border_color: Theme.line,
			border_width: 1,
			radius: Theme.radius,
		}),
		Widgets.note("A darker frame was the first to draw one or more recorded cycles; a lighter one drew no new cycle. Each column shows the longest cycle, costliest frame, or largest list pass that starts in it."),
		linkage_line(opened, "frame_cycle_linkage"),
		linkage_line(opened, "virtual_list_linkage"),
	]
}

linkage_line : Capture.Opened, Str -> Elem
linkage_line = |opened, name| Widgets.labelled_note("Linkage ${name}", Capture.absence(opened, name), if Capture.complete(opened, name) Theme.dim else Theme.caution)

causes : Capture.Opened, Capture.FrameDetail -> List(Elem)
causes = |opened, detail| if !Capture.complete(opened, "frame_cycle_linkage") {
	[Widgets.labelled_note("Frame cause", "cause not recorded: ${Capture.absence(opened, "frame_cycle_linkage")}", Theme.dim)]
} else if detail.causes.is_empty() {
	[Widgets.labelled_note("Frame cause", "cause not recorded: no recorded cycle's patch reached native views before this frame", Theme.dim)]
} else {
	[Widgets.labelled_note("Frame cause", "first to draw ${detail.causes.len().to_str()} cycle(s):", Theme.ink)].concat(
		detail.causes.map(
			|cycle| Widgets.row_key({
				caption: "cycle ${cycle_name(cycle)} · ${cycle.trigger} · ${Format.ms(cycle.duration)}",
				label: "Cause ${cycle_name(cycle)}",
				selected: False,
				on_press: |current, _| Observatory.ask(current, InspectCycle(cycle)),
			}),
		),
	)
}

frame_panel : Observatory.State, Capture.Opened -> List(Elem)
frame_panel = |state, opened| match state.frame {
	None => [Widgets.note("Press a frame to see the cycles it was the first to draw.")]
	Some(detail) => {
		total = detail.layout + detail.prepaint + detail.paint
		[Widgets.labelled_note("Timeline frame title", "FRAME r${detail.run_id.to_str()} #${detail.ordinal.to_str()} · host stages ${Format.ms(total)}", Theme.ink)].concat(causes(opened, detail))
	}
}

part : Str, (Observatory.State, Observatory.State -> Bool), (Observatory.State, Capture.Opened -> List(Elem)) -> Elem
part = |name, same, draw| Gui.translate_with(
	|current| match current.capture {
		Some(opened) => Gui.col({ width: Fill, padding: 0, gap: Theme.inset }, draw(current, opened))
		None => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
	},
	{
		key: Gui.Key.from_str(name),
		get: |state| state,
		set: |_, next| next,
		on_delegate: Observatory.forward,
		memo: Some(same),
	},
)

timeline : Observatory.State, Capture.Opened -> Elem
timeline = |state, opened| {
	window = state.clock.window
	body = if state.clock.of != opened.revision {
		[Widgets.note("Reading the timeline…")]
	} else if window.span <= 0 {
		[Widgets.labelled_note("Timeline empty", "This capture records no interval on its clock.", Theme.dim)]
	} else {
		[part("Timeline chart", |a, b| inputs(a) == inputs(b) and a.clock_hover == b.clock_hover, chart)]
	}
	Gui.col({ label: "Timeline", width: Fill, padding: Theme.inset, gap: Theme.inset }, body)
}
