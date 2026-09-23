## The CPU history plot.
##
## A column of numbers says what the machine is doing now. A monitor also has to
## say what it has been doing, and a person reads a shape far faster than a
## hundred figures. The plot is anchored to its right edge, so the newest sample
## is always in the same place and the window of history slides underneath it
## rather than the bars marching across.
##
## Gaps are drawn as gaps. A sample whose CPU reading was unavailable gets a
## stub at the baseline instead of a bar, because a bar of height zero would be
## a claim the sampler never made.
import pf.Gui
import Summary
import Theme

Chart := [].{

	## The plot's height, which the axis beside it matches. The plot fills the
	## width the window gives it and hears that width through `on_size`; the
	## bars are drawn for it, so a wider window shows wider bars rather than
	## an empty margin.
	height : U32
	height = plot_height

	## The plot itself, drawn for `width` logical pixels inside its border, or
	## for the width it starts at before the window has laid it out. `capacity`
	## is the number of samples the history holds, so the horizontal pitch is
	## the width divided by the bound rather than by how full the history is.
	render : { history : List(U32), capacity : U64, width : U32, on_size : (a, Gui.EventCanvasSize => Gui.Action(a)) } -> Gui.Elem(a)
	render = render

	## The reading each gridline marks, top to bottom, for the axis beside it.
	gridline_captions : List(Str)
	gridline_captions = ["100%", "75%", "50%", "25%", "0%"]

	## The samples a history reduces to: CPU in tenths of a percent, or the
	## sentinel that means the sample carried no CPU reading.
	no_reading = 65535.U32
	loads : List(Gui.SystemMonitorSnapshot) -> List(U32)
	loads = loads
}

loads = |history| history.map(
	|snapshot| match Summary.cpu_load(snapshot) {
		None => 65535
		Some(tenths) => U64.to_u32_wrap(tenths)
	},
)

## The width the plot is drawn for until the window has laid it out.
start_width = 600.U32

plot_height = 112.U32

## The narrowest plot still gives every sample of a full history a bar.
min_width = 240.U32

stub_height = 3.U32

## Four gridlines and a baseline. The baseline is a shade stronger, because zero
## is a real reading and the quarters are only a ruler.
gridlines = |plot_width| {
	var $primitives = []
	var $step = 0
	while $step < 5 {
		y = U32.to_i32_wrap(plot_height * $step / 4)
		colour = if $step == 4 Theme.hairline else 0x1d3039
		$primitives = $primitives.append(
			Gui.rectangle({
				key: U32.to_u64($step) + 1,
				label: "Gridline ${$step.to_str()}",
				x: 0,
				y: if $step == 4 y - 1 else y,
				width: plot_width,
				height: 1,
				fill: colour,
			}),
		)
		$step = $step + 1
	}
	$primitives
}

## Bars are keyed by their position in the plot, not by the sampler's sequence.
## The sequence restarts whenever a sampler is opened, and a retained canvas
## needs keys that stay unique across a resume.
bar = |plot_width, pitch, position, load| {
	bar_width = if pitch > 1 pitch - 1 else 1
	x = U32.to_i32_wrap(plot_width) - U64.to_i32_wrap((position + 1) * U32.to_u64(pitch))
	if load == 65535 {
		Gui.rectangle({
			key: 100 + position,
			label: "Sample ${position.to_str()} unreported",
			x,
			y: U32.to_i32_wrap(plot_height - stub_height),
			width: bar_width,
			height: stub_height,
			fill: Theme.absent,
		})
	} else {
		clamped = if load > 1000 1000 else load
		scaled = clamped * plot_height / 1000
		drawn = if scaled == 0 1 else scaled
		fill = if clamped >= 800 Theme.alert else if clamped >= 600 Theme.warn else Theme.accent_deep
		Gui.rectangle({
			key: 100 + position,
			label: "Sample ${position.to_str()} load",
			x,
			y: U32.to_i32_wrap(plot_height - drawn),
			width: bar_width,
			height: drawn,
			fill,
		})
	}
}

## The newest sample sits at the right edge, so `position` counts backwards from
## the end of the history and a partly filled plot fills from the right.
## Every sample of a full history fits: the pitch is the plot's width divided
## by the bound, so no bar is ever drawn off the left edge.
bars = |history, capacity, plot_width| {
	pitch = if capacity == 0 plot_width else U64.to_u32_wrap(U32.to_u64(plot_width) / capacity)
	held = history.len()
	drawn = if held > capacity capacity else held
	var $primitives = []
	var $position = 0
	while $position < drawn {
		load = history.get(held - 1 - $position) ?? 65535
		$primitives = $primitives.append(bar(plot_width, pitch, $position, load))
		$position = $position + 1
	}
	$primitives
}

render = |props| {
	plot_width = if props.width == 0 start_width else props.width
	Gui.canvas({
		label: "CPU history plot",
		primitives: gridlines(plot_width).concat(bars(props.history, props.capacity, plot_width)),
		on_pointer: |_, _| Gui.none,
		on_size: Some(props.on_size),
		width: Fill,
		grow: True,
		height: Px(plot_height),
		min_width: Px(min_width),
		min_height: Px(plot_height),
		bg: 0x0f1c23,
		border_color: Theme.hairline,
		border_width: 1,
		radius: 8,
	})
}
