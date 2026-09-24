app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui

## A service and the latencies it last reported, in milliseconds.
Service : { id : U64, name : Str, samples : List(U32) }

## `width` is the width, inside its border, the window last laid a sparkline
## out at, or zero before it has. Every sparkline fills the same column, so
## they share it.
State : { services : List(Service), width : U32 }

samples_per_line : U64
samples_per_line = 48

## Latencies that rise and fall with the service's number, so every line has
## a shape of its own and every run draws the same lines.
latencies : U64 -> List(U32)
latencies = |id| {
	var $samples = []
	var $index = 0.U64
	while $index < samples_per_line {
		phase = (id * 7 + $index * 5) % 40
		rise = if phase < 20 phase else 40 - phase
		$samples = $samples.append(U64.to_u32_wrap(12 + rise * 3 + (id % 9)))
		$index = $index + 1
	}
	$samples
}

services : U64 -> List(Service)
services = |count| {
	var $services = []
	var $id = 1.U64
	while $id <= count {
		$services = $services.append({ id: $id, name: "service-${$id.to_str()}", samples: latencies($id) })
		$id = $id + 1
	}
	$services
}

line_height : U32
line_height = 28

## The width a sparkline is drawn for before the window has laid it out.
start_width : U32
start_width = 480

ceiling : U32
ceiling = 90

## One bar per sample, spread across the width the sparkline was laid out at,
## the newest at the right.
bars : Service, U32 -> List(Gui.CanvasPrimitive)
bars = |service, laid_out| {
	width = if laid_out == 0 start_width else laid_out
	pitch = width / U64.to_u32_wrap(samples_per_line)
	mark = if pitch > 1 pitch - 1 else 1
	service.samples.map_with_index(
		|latency, index| {
			height = (if latency > ceiling ceiling else latency) * line_height / ceiling
			x = width - (U64.to_u32_wrap(samples_per_line - index) * pitch)
			Gui.rectangle({
				key: index + 1,
				label: "Sample ${index.to_str()}",
				x: U32.to_i32_wrap(x),
				y: U32.to_i32_wrap(line_height - height),
				width: mark,
				height,
				fill: if latency >= 60 0xE07A5F else 0x81B29A,
			})
		},
	)
}

line : Service, U32 -> Gui.Elem(State)
line = |service, width| Gui.row(
	{ label: "Service ${service.name}", width: Fill, padding: 0, gap: 12, align: Center },
	[
		Gui.row({ width: Px(120), min_width: Px(120), padding: 0, gap: 0 }, [Gui.text(service.name)]),
		Gui.canvas({
			label: "Latency ${service.name}",
			primitives: bars(service, width),
			on_pointer: |_, _| Gui.Action.none,
			on_size: Some(|current, laid_out| if laid_out.width == current.width Gui.Action.none else Gui.Action.update({ ..current, width: laid_out.width })),
			width: Fill,
			grow: True,
			height: Px(line_height + 2),
			min_width: Px(96),
			min_height: Px(line_height + 2),
			bg: 0x10181C,
			border_color: 0x263238,
			border_width: 1,
		}),
	],
)

size_button : U64 -> Gui.Elem(State)
size_button = |count| Gui.button({
	caption: "${count.to_str()} services",
	label: "Show ${count.to_str()} services",
	on_press: |current, _| Gui.Action.update({ ..current, services: services(count) }),
})

render : State -> Gui.Elem(State)
render = |state| Gui.col(
	{ label: "Service latency", width: Fill, height: Fill, padding: 12, gap: 8, font_size: 13, bg: 0x0B1114, fg: 0xE6EEF0 },
	[
		Gui.row({ label: "Sizes", padding: 0, gap: 8 }, [size_button(10), size_button(100), size_button(1000)]),
		Gui.scroll({
			label: "Services",
			width: Fill,
			height: Fill,
			grow: True,
			content: Gui.col({ width: Fill, padding: 0, gap: 4 }, state.services.map(|service| line(service, state.width))),
		}),
	],
)

main : Gui.Program(State)
main = Gui.run({ init: |_access| { services: [], width: 0 }, render, window: { title: "Service latency", width: 1000, height: 700 } })
