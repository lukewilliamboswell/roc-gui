app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program exposing [Program]

State : { bytes : List(U8) }

image_bytes = |size| {
	prefix = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4096\" height=\"4096\"><path stroke=\"#315469\" d=\""
	segment = "M0 0L4096 4096L0 4096L4096 0"
	suffix = "\"/></svg>"
	body_size = size - prefix.to_utf8().len() - suffix.to_utf8().len()
	segments = List.repeat(segment, body_size.div_trunc_by(segment.to_utf8().len()))
	remainder = List.repeat(" ", body_size % segment.to_utf8().len())
	"${prefix}${Str.join_with(segments, "")}${Str.join_with(remainder, "")}${suffix}".to_utf8()
}

render = |state| Elem.col(
	Elem.ColProps.{ width: Fill, height: Fill, grow: True, padding: 16 },
	[
		Elem.row(
			{},
			[
				Elem.button({ label: "Load 100 KB image", name: "Load 100000 byte image", on_press: |_, _| Action.update({ bytes: image_bytes(100000) }) }),
				Elem.button({ label: "Load 1 MB image", name: "Load 1000000 byte image", on_press: |_, _| Action.update({ bytes: image_bytes(1000000) }) }),
				Elem.button({ label: "Load 10 MB image", name: "Load 10000000 byte image", on_press: |_, _| Action.update({ bytes: image_bytes(10000000) }) }),
			],
		),
		if state.bytes.is_empty() {
			Elem.text("Choose an encoded image size")
		} else {
			Elem.image(Elem.ImageProps.{ label: "Scaled image", bytes: state.bytes, format: Svg, width: Fill, height: Fill, grow: True })
		},
	],
)

main : Program(State)
main = Program.run({ init: { bytes: [] }, render, window: { title: "Image benchmark", width: 1000, height: 700 } })
