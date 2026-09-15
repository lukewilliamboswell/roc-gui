import pf.Action
import pf.Event
import pf.Timer

Studio := [].{
	ShapeKind : [Ellipse, Rectangle]
	Shape : { id : U64, name : Str, kind : ShapeKind, x : I32, y : I32, width : U32, height : U32, color : U32 }
	Keyframe : { shape_id : U64, frame : U32, x : I32, y : I32 }
	Document : { shapes : List(Shape), keyframes : List(Keyframe) }
	Drag : [Idle, Moving({ id : U64, start_x : I32, start_y : I32, origin_x : I32, origin_y : I32 })]
	Playback : [Paused, Playing(Timer.Handle)]
	State : { document : Document, selected : [None, Some(U64)], drag : Drag, undo : List(Document), redo : List(Document), next_id : U64, frame : U32, playback : Playback, status : Str }

	## The timeline runs from frame zero through `last_frame`, drawn across a
	## track that starts at `track_x0` and spans `track_span` logical pixels.
	last_frame : U32
	last_frame = 120
	track_x0 : I32
	track_x0 = 8
	track_span : I32
	track_span = 1144

	frame_to_x : U32 -> I32
	frame_to_x = |frame| track_x0 + (U32.to_i32_wrap(frame) * track_span) / U32.to_i32_wrap(last_frame)

	frame_from_x : I32 -> U32
	frame_from_x = |x| {
		clamped = if x < track_x0 track_x0 else if x > track_x0 + track_span track_x0 + track_span else x
		I32.to_u32_wrap(((clamped - track_x0) * U32.to_i32_wrap(last_frame) + track_span / 2) / track_span)
	}

	initial : State
	initial = {
		document: { shapes: [
			{ id: 1, name: "Title card", kind: Rectangle, x: 80, y: 70, width: 240, height: 120, color: 0x4f7cac },
			{ id: 2, name: "Accent", kind: Ellipse, x: 380, y: 160, width: 140, height: 140, color: 0xe07a5f },
		], keyframes: [] },
		selected: Some(1), drag: Idle, undo: [], redo: [], next_id: 3,
		frame: 0, playback: Paused, status: "Ready",
	}

	add_rectangle = |state| add_shape(state, Rectangle)
	add_ellipse = |state| add_shape(state, Ellipse)
	add_shape = |state, kind| {
		id = state.next_id
		name = match kind {
			Rectangle => "Rectangle ${id.to_str()}"
			Ellipse => "Ellipse ${id.to_str()}"
		}
		placed = state.document.shapes.len()
		step = U64.to_i32_wrap(placed % 8)
		cycle = U64.to_i32_wrap((placed / 8) % 4)
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
				Ok(shape) => { ..state, selected: Some(id), drag: Moving({ id, start_x: event.x, start_y: event.y, origin_x: shape.x, origin_y: shape.y }), undo: state.undo.append(state.document), redo: [], status: "Moving ${shape.name}" }
			}
		}
		Move => match state.drag {
			Idle => state
			Moving(move) => { ..state, document: { ..state.document, shapes: state.document.shapes.map(|shape| if shape.id == move.id { ..shape, x: move.origin_x + event.x - move.start_x, y: move.origin_y + event.y - move.start_y } else shape) } }
		}
		End => { ..state, drag: Idle, status: "Move committed" }
	}
	pointer : State, Event.CanvasPointer => Action.Action(State)
	pointer = |state, event| Action.update(pointer_state(state, event))

	scrub_to = |state, x| {
		frame = frame_from_x(x)
		apply_frame({ ..state, frame, status: "Scrubbed to frame ${frame.to_str()}" })
	}
	## Pressing or dragging on the timeline track scrubs to that frame.
	timeline_pointer : State, Event.CanvasPointer => Action.Action(State)
	timeline_pointer = |state, event| match event.phase {
		End => Action.none
		Begin => Action.update(scrub_to(state, event.x))
		Move => Action.update(scrub_to(state, event.x))
	}

	undo = |state| match state.undo.last() {
		Err(_) => state
		Ok(previous) => { ..state, document: previous, undo: state.undo.drop_last(1), redo: state.redo.append(state.document), drag: Idle, status: "Undid edit" }
	}
	redo = |state| match state.redo.last() {
		Err(_) => state
		Ok(next) => { ..state, document: next, redo: state.redo.drop_last(1), undo: state.undo.append(state.document), drag: Idle, status: "Redid edit" }
	}

	add_keyframe = |state| match state.selected {
		None => { ..state, status: "Select a shape before adding a keyframe" }
		Some(id) => match state.document.shapes.find_first(|shape| shape.id == id) {
			Err(_) => state
			Ok(shape) => {
				without = state.document.keyframes.keep_if(|key| !(key.shape_id == id and key.frame == state.frame))
				key = { shape_id: id, frame: state.frame, x: shape.x, y: shape.y }
				{ ..state, document: { ..state.document, keyframes: without.append(key) }, undo: state.undo.append(state.document), redo: [], status: "Keyframe for ${shape.name} at frame ${state.frame.to_str()}" }
			}
		}
	}

	apply_frame = |state| {
		shapes = state.document.shapes.map(|shape| match state.document.keyframes.keep_if(|key| key.shape_id == shape.id and key.frame <= state.frame).last() {
			Err(_) => shape
			Ok(key) => { ..shape, x: key.x, y: key.y }
		})
		{ ..state, document: { ..state.document, shapes } }
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

	wait_frame = |state, handle| Action.task({
		pending: state,
		run: || Timer.next!(handle),
		resolve: |latest, result| match result {
			Canceled => Action.update({ ..latest, playback: Paused, status: "Paused at ${frame_status(latest.frame)}" })
			Fired => {
				next = apply_frame({ ..latest, frame: if latest.frame >= last_frame 0 else latest.frame + 1 })
				wait_frame(next, handle)
			}
		},
	})
	play! = |state| match Timer.start!({ interval_ms: 50 }) {
		Err(_) => Action.update({ ..state, status: "Playback timer unavailable" })
		Ok(handle) => wait_frame({ ..state, playback: Playing(handle), status: "Playing" }, handle)
	}
	pause! = |state, handle| {
		_ = Timer.cancel!(handle)
		Action.update({ ..state, playback: Paused, status: "Paused at ${frame_status(state.frame)}" })
	}
}
