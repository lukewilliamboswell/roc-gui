import Action exposing [Action]
import Event
import Gui

## A declarative UI tree whose event handlers transition application state `a`.
## Use `text`, `button`, `checkbox`, `row`, and `col` to build a tree, and
## `translate` or `lift` to embed UI over smaller component state.
Elem(a) :: [
	Boundary(a -> Elem(a)),
	Button({ label : List(Elem(a)), name : Str, on_press : (a, Event.Press -> Action(a)) }),
	Checkbox(CheckboxProps(a)),
	Column(List(Elem(a))),
	Row(List(Elem(a))),
	Text(Str),
].{

	## Properties for `checkbox`. `label` is both visible text and the stable
	## semantic name used by specifications. `on_change` receives the requested
	## checked state. The common visual fields mirror `Gui.Style`; defaults let a
	## record literal name only the properties it changes.
	CheckboxProps(a) := {
		label : Str,
		checked : Bool,
		enabled : Bool ?? True,
		on_change : (a, Event.Check -> Action(a)),
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
	}

	## Display literal text.
	text : Str -> Elem(a)
	text = |value| Text(value)

	## Display a named button and handle presses. `name` is its stable semantic
	## locator; `label` is the element rendered inside it.
	button : { label : Elem(a), name : Str, on_press : a, Event.Press -> Action(a) } -> Elem(a)
	button = |props| Button({ label: [props.label], name: props.name, on_press: props.on_press })

	## Display a controlled checkbox. A handler must return the state containing
	## the next `checked` value for the visual state to change.
	checkbox : CheckboxProps(a) -> Elem(a)
	checkbox = |props| Checkbox(props)

	## Lay out children horizontally in order.
	row : List(Elem(a)) -> Elem(a)
	row = |children| Row(children)

	## Lay out children vertically in order.
	col : List(Elem(a)) -> Elem(a)
	col = |children| Column(children)

	## Adapt an already-built child tree to parent state.
	lift : Elem(child), (parent -> child), (parent, child -> parent) -> Elem(parent)
	lift = |elem, get_child, set_child| match elem {
		Text(value) => Text(value)
		Row(children) => Row(children.map(|child| lift(child, get_child, set_child)))
		Column(children) => Column(children.map(|child| lift(child, get_child, set_child)))
		Button(button_value) => {
			child_handler = button_value.on_press
			parent_handler = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Button({
				label: button_value.label.map(|label| lift(label, get_child, set_child)),
				name: button_value.name,
				on_press: parent_handler,
			})
		}
		Checkbox(checkbox_value) => {
			child_handler = checkbox_value.on_change
			parent_handler = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Checkbox(
				CheckboxProps.{
					label: checkbox_value.label,
					checked: checkbox_value.checked,
					enabled: checkbox_value.enabled,
					on_change: parent_handler,
					gap: checkbox_value.gap,
					padding: checkbox_value.padding,
					width: checkbox_value.width,
					height: checkbox_value.height,
					grow: checkbox_value.grow,
					bg: checkbox_value.bg,
					hover_bg: checkbox_value.hover_bg,
					active_bg: checkbox_value.active_bg,
					fg: checkbox_value.fg,
					border_color: checkbox_value.border_color,
					border_width: checkbox_value.border_width,
					radius: checkbox_value.radius,
					font_size: checkbox_value.font_size,
					overflow_x: checkbox_value.overflow_x,
					overflow_y: checkbox_value.overflow_y,
				},
			)
		}
		Boundary(child_renderer) => {
			parent_renderer = |parent| lift(child_renderer(get_child(parent)), get_child, set_child)
			Boundary(parent_renderer)
		}
	}

	## Build a state boundary that renders child state and maps its actions back
	## into parent state.
	translate : (child -> Elem(child)), (parent -> child), (parent, child -> parent) -> Elem(parent)
	translate = |render_child, get_child, set_child| {
		render_parent = |parent| lift(render_child(get_child(parent)), get_child, set_child)
		Boundary(render_parent)
	}

	## Reveal an element descriptor. This supports platform-side traversal and
	## libraries that transform element trees.
	inspect : Elem(a) -> [
		Boundary(a -> Elem(a)),
		Button({ label : List(Elem(a)), name : Str, on_press : (a, Event.Press -> Action(a)) }),
		Checkbox(CheckboxProps(a)),
		Column(List(Elem(a))),
		Row(List(Elem(a))),
		Text(Str),
	]
	inspect = |value| match value {
		Boundary(renderer) => Boundary(renderer)
		Button(button_value) => Button(button_value)
		Checkbox(checkbox_value) => Checkbox(checkbox_value)
		Column(children) => Column(children)
		Row(children) => Row(children)
		Text(text_value) => Text(text_value)
	}
}
