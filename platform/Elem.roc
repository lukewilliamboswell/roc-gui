import Action exposing [Action]
import Event

Elem(a) := [
	Boundary(Box((a -> Elem(a)))),
	Button({ label : Box(Elem(a)), on_press : Box((a, Event.Press -> Action(a))) }),
	Column(List(Elem(a))),
	Row(List(Elem(a))),
	Text(Str),
].{
	text : Str -> Elem(a)
	text = |value| Text(value)

	button : { label : Elem(a), on_press : a, Event.Press -> Action(a) } -> Elem(a)
	button = |props| Button({ label: Box.box(props.label), on_press: Box.box(props.on_press) })

	row : List(Elem(a)) -> Elem(a)
	row = |children| Row(children)

	col : List(Elem(a)) -> Elem(a)
	col = |children| Column(children)

	lift : Elem(child), (parent -> child), (parent, child -> parent) -> Elem(parent)
	lift = |elem, get_child, set_child| match elem {
		Text(value) => Text(value)
		Row(children) => Row(children.map(|child| lift(child, get_child, set_child)))
		Column(children) => Column(children.map(|child| lift(child, get_child, set_child)))
		Button(button_value) => {
			child_handler = Box.unbox(button_value.on_press)
			parent_handler = |parent, event| match Action.inspect(child_handler(get_child(parent), event)) {
				NoChange => Action.none
				Update(next_child) => Action.update(set_child(parent, next_child))
			}
			Button({
				label: Box.box(lift(Box.unbox(button_value.label), get_child, set_child)),
				on_press: Box.box(parent_handler),
			})
		}
		Boundary(renderer_box) => {
			child_renderer = Box.unbox(renderer_box)
			parent_renderer = |parent| lift(child_renderer(get_child(parent)), get_child, set_child)
			Boundary(Box.box(parent_renderer))
		}
	}

	translate : (child -> Elem(child)), (parent -> child), (parent, child -> parent) -> Elem(parent)
	translate = |render_child, get_child, set_child| {
		render_parent = |parent| lift(render_child(get_child(parent)), get_child, set_child)
		Boundary(Box.box(render_parent))
	}

	inspect : Elem(a) -> [
		Boundary(Box((a -> Elem(a)))),
		Button({ label : Box(Elem(a)), on_press : Box((a, Event.Press -> Action(a))) }),
		Column(List(Elem(a))),
		Row(List(Elem(a))),
		Text(Str),
	]
	inspect = |value| match value {
		Boundary(renderer) => Boundary(renderer)
		Button(button_value) => Button(button_value)
		Column(children) => Column(children)
		Row(children) => Row(children)
		Text(text_value) => Text(text_value)
	}
}
