import pf.Action
import pf.Elem
import pf.Gui
import Studio

Render := [].{
	render = |state| {
		layer_rows = state.document.shapes.map(|shape| Elem.text(if state.selected == Some(shape.id) "● ${shape.name}" else "  ${shape.name}"))
		selection_text = match state.selected {
			None => "No selection"
			Some(id) => "Selected layer ${id.to_str()}"
		}
		play_control = match state.playback {
			Paused => Elem.button({ label: "Play", name: "Play", on_press: |current, _| Studio.play!(current) })
			Playing(handle) => Elem.button({ label: "Pause", name: "Pause", on_press: |current, _| Studio.pause!(current, handle) })
		}
		Elem.col({ gap: 12, padding: 16, height: Fill, bg: Rgb(0x172126), fg: Rgb(0xf4f1de) }, [
		Elem.row({ gap: 8 }, [
			Elem.text("Animation Studio"),
			Elem.button({ label: "Rectangle", name: "Add rectangle", on_press: |current, _| Action.update(Studio.add_rectangle(current)) }),
			Elem.button({ label: "Ellipse", name: "Add ellipse", on_press: |current, _| Action.update(Studio.add_ellipse(current)) }),
			Elem.button({ label: "Undo", name: "Undo", on_press: |current, _| Action.update(Studio.undo(current)) }),
			Elem.button({ label: "Redo", name: "Redo", on_press: |current, _| Action.update(Studio.redo(current)) }),
		]),
		Elem.row({ gap: 12, grow: True, height: Fill }, [
			Elem.panel({ label: "Layers", width: Px(220), height: Fill }, [Elem.text("Layers: ${state.document.shapes.len().to_str()}")].concat(layer_rows)),
			Elem.canvas(Elem.CanvasProps.{
				label: "Stage",
				primitives: state.document.shapes.map(|shape| primitive(shape, state.selected)),
				on_pointer: Studio.pointer,
				grow: True, width: Fill, height: Fill, bg: Rgb(0xf7f3e8), border_color: Rgb(0x48666b), border_width: 1, radius: 6,
			}),
			Elem.panel({ label: "Inspector", width: Px(220), height: Fill }, [
				Elem.text(selection_text),
				Elem.text("Frame ${state.frame.to_str()} / 120"),
				Elem.text("Keyframes: ${state.document.keyframes.len().to_str()}"),
			]),
		]),
		Elem.panel({ label: "Timeline", gap: 8 }, [
			Elem.row({ gap: 8 }, [
				Elem.button({ label: "−10", name: "Scrub backward", on_press: |current, _| Action.update(Studio.scrub_back(current)) }),
				play_control,
				Elem.button({ label: "+10", name: "Scrub forward", on_press: |current, _| Action.update(Studio.scrub_forward(current)) }),
				Elem.button({ label: "Add keyframe", name: "Add keyframe", on_press: |current, _| Action.update(Studio.add_keyframe(current)) }),
				Elem.text("Frame: ${state.frame.to_str()}"),
			]),
		]),
		Elem.text(state.status),
		])
	}
}

primitive = |shape, selected| {
	stroke = if selected == Some(shape.id) Rgb(0x1d3557) else Default
	stroke_width = if selected == Some(shape.id) 3 else 0
	match shape.kind {
		Rectangle => Rectangle(Elem.CanvasRectangle.{ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width, radius: 8 })
		Ellipse => Ellipse(Elem.CanvasEllipse.{ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width })
	}
}
