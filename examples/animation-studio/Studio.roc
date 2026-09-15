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
		shape = { id, name, kind, x: 140, y: 120, width: 130, height: 90, color: if kind == Rectangle 0x81b29a else 0xf2cc8f }
		{ ..state, document: { ..state.document, shapes: state.document.shapes.append(shape) }, selected: Some(id), undo: state.undo.append(state.document), redo: [], next_id: id + 1, status: "Added ${name}" }
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
				{ ..state, document: { ..state.document, keyframes: without.append(key) }, undo: state.undo.append(state.document), redo: [], status: "Keyframe added at ${state.frame.to_str()}" }
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
	scrub_back = |state| apply_frame({ ..state, frame: if state.frame < 10 0 else state.frame - 10 })
	scrub_forward = |state| apply_frame({ ..state, frame: if state.frame >= 110 120 else state.frame + 10 })

	wait_frame = |state, handle| Action.task({
		pending: state,
		run: || Timer.next!(handle),
		resolve: |latest, result| match result {
			Canceled => Action.update({ ..latest, playback: Paused, status: "Paused" })
			Fired => {
				next = apply_frame({ ..latest, frame: if latest.frame >= 120 0 else latest.frame + 1 })
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
		Action.update({ ..state, playback: Paused, status: "Paused" })
	}
}
