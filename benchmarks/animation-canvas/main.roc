app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-23-c7852fd" }

import pf.Gui

Shape : { id : U64, x : I32, y : I32, color : U32 }

Drag : [Idle, Moving({ id : U64, start_x : I32, start_y : I32, origin_x : I32, origin_y : I32 })]

State : { shapes : List(Shape), drag : Drag }

presentation : U64 -> List(Shape)
presentation = |count| {
	var $shapes = []
	var $id = 1
	var $x = 8
	var $y = 8
	while $id <= count {
		$shapes = $shapes.append({ id: $id, x: $x, y: $y, color: if $id % 3 == 0 0xe07a5f else 0x81b29a })
		$x = $x + 22
		if $x > 850 {
			$x = 8
			$y = $y + 18
		}
		$id = $id + 1
	}
	$shapes
}

pointer_state = |state, event| match event.phase {
	Begin => match event.target {
		None => state
		Some(id) => match state.shapes.find_first(|shape| shape.id == id) {
			Err(_) => state
			Ok(shape) => { ..state, drag: Moving({ id, start_x: event.x, start_y: event.y, origin_x: shape.x, origin_y: shape.y }) }
		}
	}
	Move => match state.drag {
		Idle => state
		Moving(move) => { ..state, shapes: state.shapes.map(|shape| if shape.id == move.id { ..shape, x: move.origin_x + event.x - move.start_x, y: move.origin_y + event.y - move.start_y } else shape) }
	}
	End => { ..state, drag: Idle }
}

render = |state| Gui.canvas({
	label: "Presentation stage",
	primitives: state.shapes.map(|shape| Gui.rectangle({ key: shape.id, label: "Layer ${shape.id.to_str()}", x: shape.x, y: shape.y, width: 18, height: 14, fill: Rgb(shape.color), radius: 2 })),
	on_pointer: |current, event| Gui.Action.update(pointer_state(current, event)),
	width: Fill,
	height: Fill,
})

main : Gui.Program(State)
main = Gui.run({ init: |_access| { shapes: presentation(1000), drag: Idle }, render, window: { title: "Large animated presentation", width: 1000, height: 700 } })
