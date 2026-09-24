import pf.Gui

Studio := [].{
	ShapeKind : [Ellipse, Rectangle]

	## What a primitive is called wherever it is named to a person: the
	## inspector's Kind field and the accessible name of a layer's glyph.
	kind_name : ShapeKind -> Str
	kind_name = |kind| match kind {
		Rectangle => "Rectangle"
		Ellipse => "Ellipse"
	}
	Shape : { id : U64, name : Str, kind : ShapeKind, x : I32, y : I32, width : U32, height : U32, color : U32 }
	Keyframe : { shape_id : U64, frame : U32, x : I32, y : I32 }
	Document : { shapes : List(Shape), keyframes : List(Keyframe) }

	## `recorded` is whether this gesture has already put a snapshot in the undo
	## stack. A press that selects a shape and never moves it has changed
	## nothing, so it must not leave an entry for Undo to walk back through.
	Drag : [Idle, Moving({ id : U64, start_x : I32, start_y : I32, origin_x : I32, origin_y : I32, recorded : Bool })]
	Playback : [Paused, Playing(Gui.Timer.Handle)]
	State : { document : Document, selected : [None, Some(U64)], drag : Drag, undo : List(Document), redo : List(Document), next_id : U64, frame : U32, playback : Playback, status : Str }

	## The timeline runs from frame zero through `last_frame`, drawn across a
	## track that starts at `track_x0` and spans `track_span` logical pixels.
	last_frame = 120.U32
	track_x0 = 8.I32
	track_span = 1144.I32

	frame_to_x : U32 -> I32
	frame_to_x = |frame| track_x0 + (U32.to_i32_wrap(frame) * track_span) / U32.to_i32_wrap(last_frame)

	frame_from_x : I32 -> U32
	frame_from_x = |x| {
		clamped = if x < track_x0 track_x0 else if x > track_x0 + track_span track_x0 + track_span else x
		I32.to_u32_wrap(((clamped - track_x0) * U32.to_i32_wrap(last_frame) + track_span / 2) / track_span)
	}

	initial : State
	initial = {
		document: {
			shapes: [
				{ id: 1, name: "Title card", kind: Rectangle, x: 80, y: 70, width: 240, height: 120, color: 0x4f7cac },
				{ id: 2, name: "Accent", kind: Ellipse, x: 380, y: 160, width: 140, height: 140, color: 0xe07a5f },
			],
			keyframes: [],
		},
		selected: Some(1),
		drag: Idle,
		undo: [],
		redo: [],
		next_id: 3,
		frame: 0,
		playback: Paused,
		status: "Ready",
	}

	add_rectangle = |state| add_shape(state, Rectangle)
	add_ellipse = |state| add_shape(state, Ellipse)
	add_shape = |state, kind| {
		id = state.next_id

		## A layer is named for what it is for, never for what shape it is: the
		## glyph beside the name already says rectangle or ellipse, and a row
		## that says it twice has one thing in it doing no work. Until someone
		## renames it, a new layer is only a layer.
		name = "Layer ${id.to_str()}"
		placed = state.document.shapes.len()
		step = U64.to_i32_wrap(placed % 8)
		cycle = U64.to_i32_wrap((placed / 8) % 12)
		shape = { id, name, kind, x: 300 + step * 40 + cycle * 18, y: 110 + step * 18 + cycle * 9, width: 130, height: 90, color: if kind == Rectangle 0x81b29a else 0xf2cc8f }
		{ ..state, document: { ..state.document, shapes: state.document.shapes.append(shape) }, selected: Some(id), undo: state.undo.append(state.document), redo: [], next_id: id + 1, status: "Added ${name}" }
	}

	select_shape = |state, id| match state.document.shapes.find_first(|shape| shape.id == id) {
		Err(_) => state
		Ok(shape) => { ..state, selected: Some(id), status: "Selected ${shape.name}" }
	}

	pointer_state = |state, event| match event.phase {
		Begin => match event.target {
			None => { ..state, selected: None, drag: Idle, status: "Canvas selected" }
			Some(id) => match state.document.shapes.find_first(|shape| shape.id == id) {
				Err(_) => state

				## Pressing a shape selects it. It does not yet edit it, so it
				## leaves no history entry: a person who clicks a layer to look
				## at it should not find Undo lit up with nothing to undo.
				Ok(shape) => { ..state, selected: Some(id), drag: Moving({ id, start_x: event.x, start_y: event.y, origin_x: shape.x, origin_y: shape.y, recorded: False }), status: "Selected ${shape.name}" }
			}
		}
		Move => match state.drag {
			Idle => state
			Moving(move) => {
				x = move.origin_x + event.x - move.start_x
				y = move.origin_y + event.y - move.start_y
				placed = { ..state.document, shapes: state.document.shapes.map(|shape| if shape.id == move.id { ..shape, x, y } else shape) }

				## A position belongs to the frame it was set on, not to the
				## shape, so a movement is recorded there as it happens. Without
				## this a drag changed the shape's one stored position and the
				## next scrub overwrote it from the keys, silently losing the
				## move.
				##
				## Every shape, not only one that has been keyed already. Two
				## shapes that look alike behaved differently depending on
				## whether someone had happened to press Add keyframe on one of
				## them earlier, and nothing on the stage said which was which. A
				## shape's first key is also its only key, and one key is a
				## constant position at every frame, so this costs a static
				## layout nothing but a marker on the timeline.
				moved = record_key(placed, move.id, state.frame, x, y)

				## The first movement of a gesture is the edit, so that is where
				## the snapshot belongs, and it is the document as it stood
				## before the gesture began.
				if move.recorded {
					{ ..state, document: moved }
				} else {
					{ ..state, document: moved, drag: Moving({ ..move, recorded: True }), undo: state.undo.append(state.document), redo: [], status: "Moving ${shape_name(state, move.id)}" }
				}
			}
		}

		## A release only commits what a movement started. Reporting "Move
		## committed" after a press on bare canvas says something that did not
		## happen.
		End => match state.drag {
			Moving(move) if move.recorded => { ..state, drag: Idle, status: "Move committed" }
			_ => { ..state, drag: Idle }
		}
	}

	shape_name = |state, id| match state.document.shapes.find_first(|shape| shape.id == id) {
		Ok(shape) => shape.name
		Err(_) => "layer"
	}
	pointer : State, Gui.Event.CanvasPointer => Gui.Action(State)
	pointer = |state, event| Gui.Action.update(pointer_state(state, event))

	scrub_to = |state, x| {
		frame = frame_from_x(x)
		apply_frame({ ..state, frame, status: "Scrubbed to frame ${frame.to_str()}" })
	}

	## Pressing or dragging on the timeline track scrubs to that frame.
	timeline_pointer : State, Gui.Event.CanvasPointer => Gui.Action(State)
	timeline_pointer = |state, event| match event.phase {
		End => Gui.Action.none
		Begin => Gui.Action.update(scrub_to(state, event.x))
		Move => Gui.Action.update(scrub_to(state, event.x))
	}

	undo = |state| match state.undo.last() {
		Err(_) => state
		Ok(previous) => restore({ ..state, undo: state.undo.drop_last(1), redo: state.redo.append(state.document) }, previous, "Undid edit")
	}
	redo = |state| match state.redo.last() {
		Err(_) => state
		Ok(next) => restore({ ..state, redo: state.redo.drop_last(1), undo: state.undo.append(state.document) }, next, "Redid edit")
	}

	## One key per shape per frame: recording at a frame that already has one
	## replaces it rather than leaving two for the frame to choose between.
	##
	## Kept in frame order. `apply_frame` reads the keys either side of the
	## current frame, which are only the neighbouring keys if the list is ordered
	## by frame; appended in the order a person happened to record them, a key
	## set at frame 10 after one set at frame 40 would win everywhere past frame
	## 40.
	record_key : Document, U64, U32, I32, I32 -> Document
	record_key = |document, id, frame, x, y| {
		without = document.keyframes.keep_if(|key| !(key.shape_id == id and key.frame == frame))
		keyframes = List.sort_with(without.append({ shape_id: id, frame, x, y }), |left, right| if left.frame < right.frame Before else if left.frame > right.frame After else Same)
		{ ..document, keyframes }
	}

	add_keyframe = |state| match state.selected {
		None => { ..state, status: "Select a shape before adding a keyframe" }
		Some(id) => match state.document.shapes.find_first(|shape| shape.id == id) {
			Err(_) => state
			Ok(shape) => {
				..state,
				document: record_key(state.document, id, state.frame, shape.x, shape.y),
				undo: state.undo.append(state.document),
				redo: [],
				status: "Keyframe for ${shape.name} at frame ${state.frame.to_str()}",
			}
		}
	}

	## Where a key puts a shape at a frame that is not the key's own. Two keys
	## thirty frames apart describe a movement, and the frames between them are
	## where that movement happens.
	between : I32, I32, U32, U32, U32 -> I32
	between = |from, to, at, start, end| {
		span = U32.to_i32_wrap(end - start)
		elapsed = U32.to_i32_wrap(at - start)
		travelled = (to - from) * elapsed

		## Rounded to a whole pixel away from zero on a tie, so a movement reads
		## the same travelled left as travelled right.
		rounded = if travelled < 0 (travelled - span / 2) / span else (travelled + span / 2) / span
		from + rounded
	}

	## A frame is a pure function of the keys and the frame number. Between two
	## keys a shape is partway through the movement they describe; before the
	## first and after the last there is nothing to move towards, so that key
	## holds. A shape with no keys at all stays where it was put.
	##
	## Taking only the last key at or before the frame was two defects at once. A
	## shape held still between its keys and then jumped, which is not the motion
	## anyone recorded. And before its first key there was no key to take, so the
	## position was left at whatever the previously applied frame had written into
	## the document; playback wraps from the last frame to zero, so every loop
	## started where the previous one ended and the animation drifted.
	apply_frame = |state| {
		shapes = state.document.shapes.map(
			|shape| {
				keys = state.document.keyframes.keep_if(|key| key.shape_id == shape.id)
				match keys.keep_if(|key| key.frame <= state.frame).last() {
					Err(_) => match keys.first() {
						Err(_) => shape
						Ok(next) => { ..shape, x: next.x, y: next.y }
					}
					Ok(previous) => match keys.keep_if(|key| key.frame > state.frame).first() {
						Err(_) => { ..shape, x: previous.x, y: previous.y }
						Ok(next) => {
							..shape,
							x: between(previous.x, next.x, state.frame, previous.frame, next.frame),
							y: between(previous.y, next.y, state.frame, previous.frame, next.frame),
						}
					}
				}
			},
		)
		{ ..state, document: { ..state.document, shapes } }
	}

	## Restoring a document is not only swapping the shapes. The frame a person
	## is standing on still has to hold, or the stage shows positions the
	## timeline disagrees with until the next scrub; and a selection of a layer
	## the restored document no longer contains has to go, or the inspector
	## empties while Add keyframe silently does nothing.
	restore : State, Document, Str -> State
	restore = |state, document, status| {
		settled = apply_frame({ ..state, document, drag: Idle, status })
		keeps = match settled.selected {
			None => False
			Some(id) => match settled.document.shapes.find_first(|shape| shape.id == id) {
				Ok(_) => True
				Err(_) => False
			}
		}
		if keeps settled else { ..settled, selected: None }
	}
	frame_status = |frame| "Frame ${frame.to_str()} of ${last_frame.to_str()}"
	scrub_back = |state| match state.frame == 0 {
		True => { ..state, status: "Already at the first frame" }
		False => {
			frame = if state.frame < 10 0 else state.frame - 10
			apply_frame({ ..state, frame, status: frame_status(frame) })
		}
	}
	scrub_forward = |state| match state.frame >= last_frame {
		True => { ..state, status: "Already at the last frame" }
		False => {
			frame = if state.frame + 10 >= last_frame last_frame else state.frame + 10
			apply_frame({ ..state, frame, status: frame_status(frame) })
		}
	}

	wait_frame = |state, handle| Gui.Action.task({
		pending: state,
		run: || handle.next!(),
		resolve: |latest, result| match result {
			Canceled => Gui.Action.update({ ..latest, playback: Paused, status: "Paused at ${frame_status(latest.frame)}" })
			Fired => {
				next = apply_frame({ ..latest, frame: if latest.frame >= last_frame 0 else latest.frame + 1 })
				wait_frame(next, handle)
			}
		},
	})
	play! = |state| match Gui.Timer.start!({ interval_ms: 50 }) {
		Err(_) => Gui.Action.update({ ..state, status: "Playback timer unavailable" })
		Ok(handle) => wait_frame({ ..state, playback: Playing(handle), status: "Playing" }, handle)
	}
	pause! = |state, handle| {
		_ = handle.cancel!()
		Gui.Action.update({ ..state, playback: Paused, status: "Paused at ${frame_status(state.frame)}" })
	}
}
