import Action exposing [Action]
import Event

Elem(a) := [
	Boundary(a -> Elem(a)),
	Button({ label : List(Elem(a)), name : Str, on_press : (a, Event.Press -> Action(a)) }),
	Column(List(Elem(a))),
	Row(List(Elem(a))),
	Text(Str),
].{
	text : Str -> Elem(a)
	text = |value| Text(value)

	button : { label : Elem(a), name : Str, on_press : a, Event.Press -> Action(a) } -> Elem(a)
	button = |props| Button({ label: [props.label], name: props.name, on_press: props.on_press })

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
			child_handler = button_value.on_press
			parent_handler = |parent, event| match Action.inspect(child_handler(get_child(parent), event)) {
				NoChange => Action.none
				Update(next_child) => Action.update(set_child(parent, next_child))
			}
			Button({
				label: button_value.label.map(|label| lift(label, get_child, set_child)),
				name: button_value.name,
				on_press: parent_handler,
			})
		}
		Boundary(child_renderer) => {
			parent_renderer = |parent| lift(child_renderer(get_child(parent)), get_child, set_child)
			Boundary(parent_renderer)
		}
	}

	translate : (child -> Elem(child)), (parent -> child), (parent, child -> parent) -> Elem(parent)
	translate = |render_child, get_child, set_child| {
		render_parent = |parent| lift(render_child(get_child(parent)), get_child, set_child)
		Boundary(render_parent)
	}

	inspect : Elem(a) -> [
		Boundary(a -> Elem(a)),
		Button({ label : List(Elem(a)), name : Str, on_press : (a, Event.Press -> Action(a)) }),
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
