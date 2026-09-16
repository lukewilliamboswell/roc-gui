import pf.Action
import pf.Elem
import pf.Gui
import Studio

## Two icons small enough to live in the executable. A compile-time file import
## needs no capability and no store: the bytes are the program's own.
import "icons/shape-rectangle.svg" as rectangle_glyph : List(U8)
import "icons/shape-ellipse.svg" as ellipse_glyph : List(U8)

Render := [].{
	render = |state| {
		selected_shape = match state.selected {
			None => Err(NoSelection)
			Some(id) => state.document.shapes.find_first(|shape| shape.id == id)
		}
		play_control = match state.playback {
			Paused => transport("Play", "Play", |current, _| Studio.play!(current))
			Playing(handle) => transport("Pause", "Pause", |current, _| Studio.pause!(current, handle))
		}
		Elem.col(Elem.ColProps.{ label: "Animation studio", gap: 12, padding: 16, width: Fill, height: Fill, grow: True, bg: Rgb(0x172126), fg: Rgb(0xf4f1de), overflow_y: Clip }, [
			toolbar(state),
			Elem.row(Elem.RowProps.{ label: "Workspace", gap: 12, grow: True, width: Fill, height: Fill, overflow_y: Clip }, [
				layers_panel(state),
				Elem.canvas(Elem.CanvasProps.{
					label: "Stage",
					primitives: state.document.shapes.map(|shape| primitive(shape, state.selected)),
					on_pointer: Studio.pointer,
					grow: True, width: Fill, height: Fill, bg: Rgb(0xf7f3e8), border_color: Rgb(0x48666b), border_width: 1, radius: 6,
				}),
				inspector_panel(selected_shape, state),
			]),
			timeline_panel(state, play_control),
			status_bar(state),
		])
	}

	## The application title is set apart from the controls it sits beside, and
	## every button caption names the action it performs.
	toolbar = |state| Elem.row(Elem.RowProps.{ label: "Toolbar", gap: 10, width: Fill }, [
		Elem.row(Elem.RowProps.{ width: Px(220), padding: 0, font_size: 20, fg: Rgb(0xf2cc8f) }, [Elem.text("Animation Studio")]),
		Elem.button({ label: "Add rectangle", name: "Add rectangle", on_press: |current, _| Action.update(Studio.add_rectangle(current)) }),
		Elem.button({ label: "Add ellipse", name: "Add ellipse", on_press: |current, _| Action.update(Studio.add_ellipse(current)) }),
		Elem.row(Elem.RowProps.{ width: Px(16) }, []),
		Elem.action_button(Elem.ActionButtonProps.{ caption: "Undo", label: "Undo", enabled: state.undo.len() > 0, on_press: |current, _| Action.update(Studio.undo(current)) }),
		Elem.action_button(Elem.ActionButtonProps.{ caption: "Redo", label: "Redo", enabled: state.redo.len() > 0, on_press: |current, _| Action.update(Studio.redo(current)) }),
	])

	## Layer rows are selectable controls in a scroll region, so a long document
	## never pushes the timeline or the status bar out of the window.
	layers_panel = |state| Elem.panel(Elem.PanelProps.{ label: "Layers", width: Px(230), height: Fill, gap: 10, overflow_y: Clip }, [
		Elem.row(Elem.RowProps.{ width: Fill, font_size: 12, fg: Rgb(0x9fb4bd) }, [Elem.text("LAYERS (${state.document.shapes.len().to_str()})")]),
		Elem.scroll(Elem.ScrollProps.{
			name: "Layer list",
			content: Elem.col(Elem.ColProps.{ label: "Layer rows", width: Fill, gap: 4 }, state.document.shapes.map(|shape| layer_row(shape, state.selected))),
		}),
	])

	## A layer's name says what it is for, never what shape it is: "Title card"
	## and "Accent" are rectangles and ellipses and read the same. The glyph is
	## the only place the stage's two primitives are told apart in the list, so
	## it carries meaning rather than repeating the caption beside it. Selection
	## is already carried by the row's ground, so no second marker is drawn.
	glyph_size = 16.U32
	kind_glyph = |shape| {
		art = match shape.kind {
			Rectangle => rectangle_glyph
			Ellipse => ellipse_glyph
		}
		Elem.row(Elem.RowProps.{ width: Px(26), padding: 0, gap: 0, justify: Center }, [
			Elem.image(Elem.ImageProps.{
				label: "${Studio.kind_name(shape.kind)} layer",
				bytes: art,
				format: Svg,
				width: Px(glyph_size), height: Px(glyph_size),
				min_width: Px(glyph_size), min_height: Px(glyph_size),
			}),
		])
	}

	layer_row = |shape, selected| {
		is_selected = selected == Some(shape.id)
		Elem.row(Elem.RowProps.{ gap: 0, width: Fill, radius: 6, bg: if is_selected Rgb(0x2b4a57) else Default }, [
			kind_glyph(shape),
			Elem.action_button(Elem.ActionButtonProps.{
				caption: shape.name,
				label: "Select ${shape.name}",
				on_press: |current, _| Action.update(Studio.select_shape(current, shape.id)),
				padding: 6, radius: 6,
				bg: if is_selected Rgb(0x2b4a57) else Rgb(0x172126),
				hover_bg: Rgb(0x35596a),
				fg: Rgb(0xf4f1de),
			}),
		])
	}

	inspector_panel = |selected_shape, state| {
		rows = match selected_shape {
			Err(_) => [Elem.text("No layer selected"), Elem.text("Select a layer or press a shape on the stage.")]
			Ok(shape) => {
				keys = state.document.keyframes.keep_if(|key| key.shape_id == shape.id).len()
				[
					Elem.row(Elem.RowProps.{ width: Fill, font_size: 17 }, [Elem.text(shape.name)]),
					field("Kind", Studio.kind_name(shape.kind)),
					field("Position", "${shape.x.to_str()}, ${shape.y.to_str()}"),
					field("Size", "${shape.width.to_str()} × ${shape.height.to_str()}"),
					field("Keyframes", keys.to_str()),
				]
			}
		}
		Elem.panel(Elem.PanelProps.{ label: "Inspector", width: Px(230), height: Fill, gap: 10, overflow_y: Clip }, [
			Elem.row(Elem.RowProps.{ width: Fill, font_size: 12, fg: Rgb(0x9fb4bd) }, [Elem.text("INSPECTOR")]),
		].concat(rows).append(
			Elem.row(Elem.RowProps.{ width: Fill, font_size: 12, fg: Rgb(0x9fb4bd) }, [Elem.text("Keyframes in document: ${state.document.keyframes.len().to_str()}")]),
		))
	}

	field = |name, value| Elem.row(Elem.RowProps.{ width: Fill, gap: 8 }, [
		Elem.row(Elem.RowProps.{ width: Px(76), fg: Rgb(0x9fb4bd), font_size: 13 }, [Elem.text(name)]),
		Elem.text(value),
	])

	transport = |caption, name, on_press| Elem.action_button(Elem.ActionButtonProps.{ caption, label: name, on_press, width: Px(96) })

	## The timeline draws a real track: ticks, a marker for every keyframe, and a
	## playhead at the current frame. Pressing the track scrubs to that frame.
	timeline_panel = |state, play_control| Elem.panel(Elem.PanelProps.{ label: "Timeline", width: Fill, gap: 10 }, [
		Elem.row(Elem.RowProps.{ width: Fill, gap: 8 }, [
			transport("−10", "Scrub backward", |current, _| Action.update(Studio.scrub_back(current))),
			play_control,
			transport("+10", "Scrub forward", |current, _| Action.update(Studio.scrub_forward(current))),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Add keyframe", label: "Add keyframe", on_press: |current, _| Action.update(Studio.add_keyframe(current)) }),
			Elem.row(Elem.RowProps.{ width: Fill, grow: True }, []),
			Elem.row(Elem.RowProps.{ font_size: 15, fg: Rgb(0xf2cc8f) }, [Elem.text("Frame ${state.frame.to_str()} of ${Studio.last_frame.to_str()}")]),
		]),
		Elem.canvas(Elem.CanvasProps.{
			label: "Timeline track",
			primitives: track_primitives(state),
			on_pointer: Studio.timeline_pointer,
			width: Px(1160), height: Px(78), bg: Rgb(0x111c21), border_color: Rgb(0x2c4149), border_width: 1, radius: 6,
		}),
		Elem.row(Elem.RowProps.{ label: "Timeline ticks", gap: 0, width: Px(1160), font_size: 12, fg: Rgb(0x9fb4bd) },
			major_ticks.map(|frame| Elem.row(Elem.RowProps.{ width: Px(191) }, [Elem.text(frame.to_str())])).append(Elem.text(Studio.last_frame.to_str()))),
	])

	## Labelled ticks, and the finer unlabelled ticks between them.
	major_ticks : List(U32)
	major_ticks = [0, 20, 40, 60, 80, 100]
	all_ticks : List(U32)
	all_ticks = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]

	track_primitives = |state| {
		head_x = Studio.frame_to_x(state.frame)
		track = [
			Rectangle(Elem.CanvasRectangle.{ key: 1, label: "Track", x: Studio.track_x0, y: 20, width: 1144, height: 18, fill: Rgb(0x1d2c33), radius: 9 }),
			Rectangle(Elem.CanvasRectangle.{ key: 2, label: "Elapsed", x: Studio.track_x0, y: 20, width: I32.to_u32_wrap(head_x - Studio.track_x0), height: 18, fill: Rgb(0x35596a), radius: 9 }),
		]
		ticks = all_ticks.map(|frame| {
			x = Studio.frame_to_x(frame)
			major = frame % 20 == 0
			Line(Elem.CanvasLine.{ key: 1000 + frame.to_u64(), label: "Tick ${frame.to_str()}", x1: x, y1: 44, x2: x, y2: if major 58 else 52, stroke: if major Rgb(0x6f8b95) else Rgb(0x3c5058), stroke_width: 1 })
		})
		markers = state.document.keyframes.map(|key| {
			x = Studio.frame_to_x(key.frame)
			Rectangle(Elem.CanvasRectangle.{ key: 100000 + key.shape_id * 200 + key.frame.to_u64(), label: "Keyframe ${key.frame.to_str()}", x: x - 5, y: 60, width: 11, height: 11, fill: Rgb(0xf2cc8f), radius: 2 })
		})
		playhead = [
			Rectangle(Elem.CanvasRectangle.{ key: 3, label: "Playhead head", x: head_x - 6, y: 2, width: 13, height: 10, fill: Rgb(0xe07a5f), radius: 2 }),
			Line(Elem.CanvasLine.{ key: 4, label: "Playhead", x1: head_x, y1: 2, x2: head_x, y2: 74, stroke: Rgb(0xe07a5f), stroke_width: 2 }),
		]
		track.concat(ticks).concat(markers).concat(playhead)
	}

	status_bar = |state| Elem.row(Elem.RowProps.{ label: "Status bar", width: Fill, padding: 10, gap: 8, bg: Rgb(0x111c21), border_color: Rgb(0x2c4149), border_width: 1, radius: 6, fg: Rgb(0xcfe0e5), font_size: 13 }, [
		Elem.text(state.status),
	])
}

primitive = |shape, selected| {
	stroke = if selected == Some(shape.id) Rgb(0x1d3557) else Default
	stroke_width = if selected == Some(shape.id) 3 else 0
	match shape.kind {
		Rectangle => Rectangle(Elem.CanvasRectangle.{ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width, radius: 8 })
		Ellipse => Ellipse(Elem.CanvasEllipse.{ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width })
	}
}
