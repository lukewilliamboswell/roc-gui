import pf.Gui
import Studio

## Two icons small enough to live in the executable. A compile-time file import
## needs no capability and no store: the bytes are the program's own.
import "icons/shape-rectangle.svg" as rectangle_glyph : List(U8)
import "icons/shape-ellipse.svg" as ellipse_glyph : List(U8)

## The studio's palette and type scale. Every colour and every size the window
## uses is named here, so a panel cannot quietly drift from its neighbour and
## nothing falls back to a host default that belongs to some other application.
##
## The ground is a cold slate, the stage is warm paper, and exactly two accents
## carry meaning: amber marks the timeline — the frame counter, the keyframes a
## person recorded — and coral is the playhead alone, the one thing that moves.
ground : Gui.Color
ground = 0x172126

sunken : Gui.Color
sunken = 0x111c21

raised : Gui.Color
raised = 0x1d2c33

edge : Gui.Color
edge = 0x2c4149

stage_edge : Gui.Color
stage_edge = 0x48666b

paper : Gui.Color
paper = 0xf7f3e8

ink : Gui.Color
ink = 0xf4f1de

ink_soft : Gui.Color
ink_soft = 0xcfe0e5

ink_quiet : Gui.Color
ink_quiet = 0x9fb4bd

amber : Gui.Color
amber = 0xf2cc8f

coral : Gui.Color
coral = 0xe07a5f

control : Gui.Color
control = 0x24404a

control_hover : Gui.Color
control_hover = 0x2f5462

control_press : Gui.Color
control_press = 0x1b3039

control_off : Gui.Color
control_off = 0x1a272d

control_off_ink : Gui.Color
control_off_ink = 0x5d747d

row_selected : Gui.Color
row_selected = 0x2b4a57

row_hover : Gui.Color
row_hover = 0x35596a

## Type. Nothing is left at the host default size, because a window in which
## every caption and every value is whatever size the platform happened to pick
## has no voice of its own.
title_size = 20.U32

name_size = 17.U32

read_size = 15.U32

body_size = 14.U32

label_size = 13.U32

caps_size = 12.U32

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
		Gui.col(
			{ label: "Animation studio", gap: 12, padding: 16, width: Fill, height: Fill, grow: True, bg: ground, fg: ink, font_size: body_size, overflow_y: Clip },
			[
				toolbar(state),
				Gui.row(
					{ label: "Workspace", gap: 12, grow: True, width: Fill, height: Fill, overflow_y: Clip },
					[
						layers_panel(state),
						Gui.canvas({
							label: "Stage",
							primitives: state.document.shapes.map(|shape| primitive(shape, state.selected)),
							on_pointer: Studio.pointer,
							grow: True,
							width: Fill,
							height: Fill,
							bg: paper,
							border_color: stage_edge,
							border_width: 1,
							radius: 6,
						}),
						inspector_panel(selected_shape, state),
					],
				),
				timeline_panel(state, play_control),
				status_bar(state),
			],
		)
	}

	## The application title is set apart from the controls it sits beside, and
	## every button caption names the action it performs.
	toolbar = |state| Gui.row(
		{ label: "Toolbar", gap: 10, width: Fill, align: Center },
		[
			Gui.row({ width: Px(220), padding: 0, font_size: title_size, font_weight: 600, fg: amber, align: Center }, [Gui.text("Animation Studio")]),
			command("Add rectangle", "Add rectangle", True, Auto, |current, _| Gui.update(Studio.add_rectangle(current))),
			command("Add ellipse", "Add ellipse", True, Auto, |current, _| Gui.update(Studio.add_ellipse(current))),
			Gui.row({ width: Px(16) }, []),
			command("Undo", "Undo", state.undo.len() > 0, Px(72), |current, _| Gui.update(Studio.undo(current))),
			command("Redo", "Redo", state.redo.len() > 0, Px(72), |current, _| Gui.update(Studio.redo(current))),
		],
	)

	## Layer rows are selectable controls in a scroll region, so a long document
	## never pushes the timeline or the status bar out of the window.
	layers_panel = |state| Gui.panel(
		{ label: "Layers", width: Px(230), height: Fill, gap: 10, bg: sunken, border_color: edge, overflow_y: Clip },
		[
			Gui.row({ width: Fill, font_size: caps_size, font_weight: 600, fg: ink_quiet }, [Gui.text("LAYERS (${state.document.shapes.len().to_str()})")]),
			Gui.scroll({
				label: "Layer list",
				content: Gui.col({ label: "Layer rows", width: Fill, gap: 4 }, state.document.shapes.map(|shape| layer_row(shape, state.selected))),
			}),
		],
	)

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
		Gui.row(
			{ width: Px(26), padding: 0, gap: 0, justify: Center },
			[
				Gui.image({
					label: "${Studio.kind_name(shape.kind)} layer",
					bytes: art,
					format: Svg,
					width: Px(glyph_size),
					height: Px(glyph_size),
					min_width: Px(glyph_size),
					min_height: Px(glyph_size),
				}),
			],
		)
	}

	layer_row = |shape, selected| {
		is_selected = selected == Some(shape.id)
		Gui.row(
			{ gap: 0, width: Fill, radius: 6, align: Center, bg: if is_selected row_selected else Default },
			[
				kind_glyph(shape),
				Gui.button({
					caption: shape.name,
					label: "Select ${shape.name}",
					on_press: |current, _| Gui.update(Studio.select_shape(current, shape.id)),
					width: Fill,
					justify: Start,
					padding: 8,
					radius: 6,
					font_size: body_size,

					## At rest a layer row is its panel, not a slab of a different
					## colour sitting beside its own glyph: the row and the control
					## inside it have to read as one thing.
					bg: if is_selected row_selected else Default,
					hover_bg: row_hover,
					active_bg: control_press,
					fg: ink,
				}),
			],
		)
	}

	inspector_panel = |selected_shape, state| {
		rows : List(Gui.Elem(Studio.State))
		rows = match selected_shape {
			Err(_) => [
				Gui.row({ width: Fill, font_size: name_size, fg: ink }, [Gui.text("No layer selected")]),
				Gui.row({ width: Fill, font_size: label_size, fg: ink_quiet }, [Gui.text("Select a layer or press a shape on the stage.")]),
			]
			Ok(shape) => {
				keys = state.document.keyframes.keep_if(|key| key.shape_id == shape.id).len()
				[
					Gui.row({ width: Fill, font_size: name_size, fg: ink }, [Gui.text(shape.name)]),
					field("Kind", Studio.kind_name(shape.kind)),
					field("Position", "${shape.x.to_str()}, ${shape.y.to_str()}"),
					field("Size", "${shape.width.to_str()} × ${shape.height.to_str()}"),
					field("Keyframes", keys.to_str()),
				]
			}
		}
		Gui.panel(
			{ label: "Inspector", width: Px(230), height: Fill, gap: 10, bg: sunken, border_color: edge, overflow_y: Clip },
			[
				Gui.row({ width: Fill, font_size: caps_size, font_weight: 600, fg: ink_quiet }, [Gui.text("INSPECTOR")]),
			].concat(rows).append(
				Gui.row({ width: Fill, font_size: caps_size, fg: ink_quiet }, [Gui.text("Keyframes in document: ${state.document.keyframes.len().to_str()}")]),
			),
		)
	}

	## A field's value is set in a monospaced face because most of them are
	## numbers that change while a person is dragging, and proportional digits
	## make a position readout jitter as it counts.
	field = |name, value| Gui.row(
		{ width: Fill, gap: 8, align: Center },
		[
			Gui.row({ width: Px(76), fg: ink_quiet, font_size: label_size }, [Gui.text(name)]),
			Gui.row({ grow: True, fg: ink, font_size: label_size, font_face: Monospace }, [Gui.text(value)]),
		],
	)

	## Every button in the window is this button. A disabled control is drawn
	## deliberately: the host's default would leave Undo at rest looking like a
	## control that simply has not been pressed yet.
	command = |caption, name, enabled, width, on_press| Gui.button({
		caption,
		label: name,
		enabled,
		on_press,
		width,
		padding: 10,
		padding_top: Px(7),
		padding_bottom: Px(7),
		radius: 6,
		font_size: body_size,
		bg: control,
		hover_bg: control_hover,
		active_bg: control_press,
		disabled_bg: control_off,
		disabled_fg: control_off_ink,
		fg: ink,
	})

	transport = |caption, name, on_press| command(caption, name, True, Px(96), on_press)

	## The timeline draws a real track: ticks, a marker for every keyframe, and a
	## playhead at the current frame. Pressing the track scrubs to that frame.
	timeline_panel = |state, play_control| Gui.panel(
		{ label: "Timeline", width: Fill, gap: 10, bg: sunken, border_color: edge },
		[
			Gui.row(
				{ width: Fill, gap: 8, align: Center },
				[
					transport("−10", "Scrub backward", |current, _| Gui.update(Studio.scrub_back(current))),
					play_control,
					transport("+10", "Scrub forward", |current, _| Gui.update(Studio.scrub_forward(current))),
					command("Add keyframe", "Add keyframe", True, Auto, |current, _| Gui.update(Studio.add_keyframe(current))),
					Gui.row({ width: Fill, grow: True }, []),

					## The frame counter is the one number in the window that changes
					## every fiftieth of a second while playback runs, so it is set in a
					## fixed-width face; proportional digits make it twitch.
					Gui.row({ font_size: read_size, fg: amber, font_face: Monospace }, [Gui.text(Studio.frame_status(state.frame))]),
				],
			),
			Gui.canvas({
				label: "Timeline track",
				primitives: track_primitives(state),
				on_pointer: Studio.timeline_pointer,
				width: Px(1160),
				height: Px(78),
				bg: ground,
				border_color: edge,
				border_width: 1,
				radius: 6,
			}),
			Gui.row({ label: "Timeline ticks", gap: 0, width: Px(1160), font_size: caps_size, font_face: Monospace, fg: ink_quiet }, major_ticks.map(|frame| Gui.row({ width: Px(191) }, [Gui.text(frame.to_str())])).append(Gui.text(Studio.last_frame.to_str()))),
		],
	)

	## Labelled ticks, and the finer unlabelled ticks between them.
	major_ticks : List(U32)
	major_ticks = [0, 20, 40, 60, 80, 100]
	all_ticks : List(U32)
	all_ticks = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]

	track_primitives = |state| {
		head_x = Studio.frame_to_x(state.frame)
		track = [
			Gui.rectangle({ key: 1, label: "Track", x: Studio.track_x0, y: 20, width: 1144, height: 18, fill: raised, radius: 9 }),
			Gui.rectangle({ key: 2, label: "Elapsed", x: Studio.track_x0, y: 20, width: I32.to_u32_wrap(head_x - Studio.track_x0), height: 18, fill: row_hover, radius: 9 }),
		]
		ticks = all_ticks.map(
			|frame| {
				x = Studio.frame_to_x(frame)
				major = frame % 20 == 0
				Gui.line({ key: 1000 + frame.to_u64(), label: "Tick ${frame.to_str()}", x1: x, y1: 44, x2: x, y2: if major 58 else 52, stroke: if major ink_quiet else 0x3c5058, stroke_width: 1 })
			},
		)
		markers = state.document.keyframes.map(
			|key| {
				x = Studio.frame_to_x(key.frame)
				Gui.rectangle({ key: 100000 + key.shape_id * 200 + key.frame.to_u64(), label: "Keyframe ${key.frame.to_str()}", x: x - 5, y: 60, width: 11, height: 11, fill: amber, radius: 2 })
			},
		)
		playhead = [
			Gui.rectangle({ key: 3, label: "Playhead head", x: head_x - 6, y: 2, width: 13, height: 10, fill: coral, radius: 2 }),
			Gui.line({ key: 4, label: "Playhead", x1: head_x, y1: 2, x2: head_x, y2: 74, stroke: coral, stroke_width: 2 }),
		]
		track.concat(ticks).concat(markers).concat(playhead)
	}

	status_bar = |state| Gui.row(
		{ label: "Status bar", width: Fill, padding: 10, gap: 8, bg: sunken, border_color: edge, border_width: 1, radius: 6, fg: ink_soft, font_size: label_size },
		[
			Gui.text(state.status),
		],
	)
}

primitive = |shape, selected| {
	stroke : Gui.Color
	stroke = if selected == Some(shape.id) 0x1d3557 else Default
	stroke_width = if selected == Some(shape.id) 3 else 0
	match shape.kind {
		Rectangle => Gui.rectangle({ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width, radius: 8 })
		Ellipse => Gui.ellipse({ key: shape.id, label: shape.name, x: shape.x, y: shape.y, width: shape.width, height: shape.height, fill: Rgb(shape.color), stroke, stroke_width })
	}
}
