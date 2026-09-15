import Action exposing [Action]
import Event
import Gui

## A declarative UI tree whose event handlers transition application state `a`.
## Use `text`, `action_button`, `checkbox`, `row`, `col`, and `panel` to build a tree, and
## `translate` or `lift` to embed UI over smaller component state.
Elem(a) :: [
	Boundary(a -> Elem(a)),
	ActionButton(ActionButtonProps(a)),
	Checkbox(CheckboxProps(a)),
	Column({ children : List(Elem(a)), props : ColProps }),
	Panel({ children : List(Elem(a)), props : PanelProps }),
	Row({ children : List(Elem(a)), props : RowProps }),
	Scroll(ScrollProps(a)),
	Text(Str),
].{

	## Properties for `col`. `label` is an optional stable semantic locator.
	## The remaining fields control the column's native layout and presentation.
	ColProps := {
		label : Str ?? "",
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

	## Properties for `row`. `label` is an optional stable semantic locator.
	## The remaining fields control the row's native layout and presentation.
	RowProps := {
		label : Str ?? "",
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

	## Properties for `panel`. Panels are padded, bordered, rounded vertical
	## surfaces by default, and carry a stable semantic `label`.
	PanelProps := {
		label : Str,
		gap : U32 ?? 8,
		padding : U32 ?? 16,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		radius : U32 ?? 8,
		font_size : U32 ?? 0,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
	}

	## Properties for `action_button`. `caption` is visible text and `label` is
	## its stable semantic name. Disabled buttons remain visible but cannot be
	## focused or dispatch presses. Visual fields use the same native style
	## vocabulary as layout controls.
	ActionButtonProps(a) := {
		caption : Str,
		label : Str,
		enabled : Bool ?? True,
		on_press : (a, Event.Press -> Action(a)),
		gap : U32 ?? 8,
		padding : U32 ?? 8,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x315469),
		hover_bg : Gui.Color ?? Rgb(0x3e6a83),
		active_bg : Gui.Color ?? Rgb(0x274453),
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		radius : U32 ?? 6,
		font_size : U32 ?? 0,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
	}

	## Properties for a vertically scrollable region. `name` is its stable
	## semantic identity for specifications and accessibility.
	ScrollAxis : [Both, Horizontal, Vertical]
	ScrollProps(a) := { axis : ScrollAxis ?? Vertical, content : Elem(a), name : Str }

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

	## Display a named text button and handle presses. `name` is its stable
	## semantic locator; `label` is its visible caption.
	button : { label : Str, name : Str, on_press : a, Event.Press -> Action(a) } -> Elem(a)
	button = |props| ActionButton(ActionButtonProps.{ caption: props.label, label: props.name, on_press: props.on_press })

	## Display a controlled, styled action button.
	action_button : ActionButtonProps(a) -> Elem(a)
	action_button = |props| ActionButton(props)

	## Display a controlled checkbox. A handler must return the state containing
	## the next `checked` value for the visual state to change.
	checkbox : CheckboxProps(a) -> Elem(a)
	checkbox = |props| Checkbox(props)

	## Lay out children horizontally in order.
	row : RowProps, List(Elem(a)) -> Elem(a)
	row = |props, children| Row({ children, props })

	## Lay out children vertically in order.
	col : ColProps, List(Elem(a)) -> Elem(a)
	col = |props, children| Column({ children, props })

	## Group children in a labelled padded, bordered, rounded vertical surface.
	panel : PanelProps, List(Elem(a)) -> Elem(a)
	panel = |props, children| Panel({ children, props })

	## Constrain `child` to the available height and allow vertical scrolling.
	scroll : ScrollProps(a) -> Elem(a)
	scroll = |props| Scroll(props)

	## Adapt an already-built child tree to parent state.
	lift : Elem(child), (parent -> child), (parent, child -> parent) -> Elem(parent)
	lift = |elem, get_child, set_child| match elem {
		Text(value) => Text(value)
		Row(value) => Row({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Column(value) => Column({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Panel(value) => Panel({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Scroll(scroll_value) => Scroll(ScrollProps.{ axis: scroll_value.axis, content: lift(scroll_value.content, get_child, set_child), name: scroll_value.name })
		ActionButton(button_value) => {
			child_handler = button_value.on_press
			parent_handler = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			ActionButton(
				ActionButtonProps.{
					caption: button_value.caption,
					label: button_value.label,
					enabled: button_value.enabled,
					on_press: parent_handler,
					gap: button_value.gap,
					padding: button_value.padding,
					width: button_value.width,
					height: button_value.height,
					grow: button_value.grow,
					bg: button_value.bg,
					hover_bg: button_value.hover_bg,
					active_bg: button_value.active_bg,
					fg: button_value.fg,
					border_color: button_value.border_color,
					border_width: button_value.border_width,
					radius: button_value.radius,
					font_size: button_value.font_size,
					overflow_x: button_value.overflow_x,
					overflow_y: button_value.overflow_y,
				},
			)
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
		ActionButton(ActionButtonProps(a)),
		Checkbox(CheckboxProps(a)),
		Column({ children : List(Elem(a)), props : ColProps }),
		Panel({ children : List(Elem(a)), props : PanelProps }),
		Row({ children : List(Elem(a)), props : RowProps }),
		Scroll(ScrollProps(a)),
		Text(Str),
	]
	inspect = |value| match value {
		Boundary(renderer) => Boundary(renderer)
		ActionButton(button_value) => ActionButton(button_value)
		Checkbox(checkbox_value) => Checkbox(checkbox_value)
		Column(children) => Column(children)
		Panel(children) => Panel(children)
		Row(children) => Row(children)
		Scroll(scroll_value) => Scroll(scroll_value)
		Text(text_value) => Text(text_value)
	}
}
