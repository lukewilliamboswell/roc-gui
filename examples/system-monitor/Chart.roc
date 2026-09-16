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
import pf.Action
import pf.Elem
import pf.Gui
import pf.SystemMonitor
import Summary
import Theme

Chart := [].{
	## The plot's exact size. Canvas primitives are placed in integer logical
	## pixels and are not scaled to the element, so the surface is fixed and the
	## layout is built to hold it rather than the other way round. The width is
	## the history bound times the horizontal pitch, so a full history is exactly
	## a full plot: no bar is ever drawn off the left edge.
	width : U32
	width = plot_width
	height : U32
	height = plot_height

	## The plot itself. `capacity` is the number of samples the history holds, so
	## the horizontal pitch is fixed by the bound rather than by how full it is.
	render : List(U32), U64 -> Elem.Elem(a)
	render = render

	## The reading each gridline marks, top to bottom, for the axis beside it.
	gridline_captions : List(Str)
	gridline_captions = ["100%", "75%", "50%", "25%", "0%"]

	## The samples a history reduces to: CPU in tenths of a percent, or the
	## sentinel that means the sample carried no CPU reading.
	no_reading = 65535.U32
	loads : List(SystemMonitor.Snapshot) -> List(U32)
	loads = loads
}

loads = |history| history.map(
	|snapshot| match Summary.cpu_load(snapshot) {
		None => 65535
		Some(tenths) => U64.to_u32_wrap(tenths)
	},
)

plot_width = 600.U32
plot_height = 112.U32
pitch = 5.U32
bar_width = 4.U32
stub_height = 3.U32

## Four gridlines and a baseline. The baseline is a shade stronger, because zero
## is a real reading and the quarters are only a ruler.
gridlines = {
	var $primitives = []
	var $step = 0
	while $step < 5 {
		y = U32.to_i32_wrap(plot_height * $step / 4)
		colour = if $step == 4 Theme.hairline else Gui.rgb(0x1d3039)
		$primitives = $primitives.append(
			Rectangle(
				Elem.CanvasRectangle.{
					key: U32.to_u64($step) + 1,
					label: "Gridline ${$step.to_str()}",
					x: 0,
					y: if $step == 4 y - 1 else y,
					width: plot_width,
					height: 1,
					fill: colour,
				},
			),
		)
		$step = $step + 1
	}
	$primitives
}

## Bars are keyed by their position in the plot, not by the sampler's sequence.
## The sequence restarts whenever a sampler is opened, and a retained canvas
## needs keys that stay unique across a resume.
bar = |position, load| {
	x = U32.to_i32_wrap(plot_width) - U64.to_i32_wrap((position + 1) * U32.to_u64(pitch))
	if load == 65535 {
		Rectangle(
			Elem.CanvasRectangle.{
				key: 100 + position,
				label: "Sample ${position.to_str()} unreported",
				x,
				y: U32.to_i32_wrap(plot_height - stub_height),
				width: bar_width,
				height: stub_height,
				fill: Theme.absent,
			},
		)
	} else {
		clamped = if load > 1000 1000 else load
		scaled = clamped * plot_height / 1000
		drawn = if scaled == 0 1 else scaled
		fill = if clamped >= 800 Theme.alert else if clamped >= 600 Theme.warn else Theme.accent_deep
		Rectangle(
			Elem.CanvasRectangle.{
				key: 100 + position,
				label: "Sample ${position.to_str()} load",
				x,
				y: U32.to_i32_wrap(plot_height - drawn),
				width: bar_width,
				height: drawn,
				fill,
			},
		)
	}
}

## The newest sample sits at the right edge, so `position` counts backwards from
## the end of the history and a partly filled plot fills from the right.
bars = |history, capacity| {
	held = history.len()
	drawn = if held > capacity capacity else held
	var $primitives = []
	var $position = 0
	while $position < drawn {
		load = history.get(held - 1 - $position) ?? 65535
		$primitives = $primitives.append(bar($position, load))
		$position = $position + 1
	}
	$primitives
}

render = |history, capacity| Elem.canvas(
	Elem.CanvasProps.{
		label: "CPU history plot",
		primitives: gridlines.concat(bars(history, capacity)),
		on_pointer: |_, _| Action.none,
		width: Px(plot_width),
		height: Px(plot_height),
		min_width: Px(plot_width),
		min_height: Px(plot_height),
		bg: Gui.rgb(0x0f1c23),
		border_color: Theme.hairline,
		border_width: 1,
		radius: 8,
	},
)
