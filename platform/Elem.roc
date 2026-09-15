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
	Textarea(TextareaProps(a)),
	Column({ children : List(Elem(a)), props : ColProps }),
	Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
	Panel({ children : List(Elem(a)), props : PanelProps }),
	Row({ children : List(Elem(a)), props : RowProps }),
	Scroll(ScrollProps(a)),
	VirtualList(VirtualListProps(a)),
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

	## Properties for a modal dialog. `label` is its stable semantic name and
	## `on_dismiss` handles Escape. Dialogs center above an input-blocking scrim.
	DialogProps(a) := {
		label : Str,
		on_dismiss : (a, Event.Dismiss => Action(a)),
		gap : U32 ?? 16,
		padding : U32 ?? 24,
		width : Gui.Length ?? Px(520),
		height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x212f37),
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		fg : Gui.Color ?? Rgb(0xeeeeea),
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		radius : U32 ?? 8,
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
		on_press : (a, Event.Press => Action(a)),
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

	## One stable row in a virtual list. `key` identifies the row independently
	## of its current index, while `content` is an ordinary element tree.
	VirtualListItem(a) := { content : Elem(a), key : U64 }

	## Properties for a viewport-driven, fixed-height list. Only rows intersecting
	## the native viewport are materialized as GPUI elements.
	VirtualListProps(a) := { items : List(VirtualListItem(a)), name : Str, row_height : U32 }

	## Properties for `checkbox`. `label` is both visible text and the stable
	## semantic name used by specifications. `on_change` receives the requested
	## checked state. The common visual fields mirror `Gui.Style`; defaults let a
	## record literal name only the properties it changes.
	CheckboxProps(a) := {
		label : Str,
		checked : Bool,
		enabled : Bool ?? True,
		on_change : (a, Event.Check => Action(a)),
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

	## Properties for a controlled multiline editor. `label` is its stable
	## semantic name. `value` remains application-owned; every edit delivers the
	## complete requested value to `on_input`. Read-only editors expose and scroll
	## text without dispatching edits.
	TextareaProps(a) := {
		label : Str,
		value : Str,
		placeholder : Str ?? "",
		enabled : Bool ?? True,
		read_only : Bool ?? False,
		on_input : (a, Event.Input => Action(a)),
		gap : U32 ?? 8,
		padding : U32 ?? 8,
		width : Gui.Length ?? Fill,
		height : Gui.Length ?? Px(160),
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x10252b),
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		radius : U32 ?? 6,
		font_size : U32 ?? 15,
		overflow_x : Gui.Overflow ?? Scroll,
		overflow_y : Gui.Overflow ?? Scroll,
	}

	## Display literal text.
	text : Str -> Elem(a)
	text = |value| Text(value)

	## Display a named text button and handle presses. `name` is its stable
	## semantic locator; `label` is its visible caption.
	button : { label : Str, name : Str, on_press : a, Event.Press => Action(a) } -> Elem(a)
	button = |props| ActionButton(ActionButtonProps.{ caption: props.label, label: props.name, on_press: props.on_press })

	## Display a controlled, styled action button.
	action_button : ActionButtonProps(a) -> Elem(a)
	action_button = |props| ActionButton(props)

	## Display a controlled checkbox. A handler must return the state containing
	## the next `checked` value for the visual state to change.
	checkbox : CheckboxProps(a) -> Elem(a)
	checkbox = |props| Checkbox(props)

	## Edit controlled multiline text. The application installs the next value
	## returned by `on_input`; use `read_only: True` for response viewers.
	textarea : TextareaProps(a) -> Elem(a)
	textarea = |props| Textarea(props)

	## Lay out children horizontally in order.
	row : RowProps, List(Elem(a)) -> Elem(a)
	row = |props, children| Row({ children, props })

	## Lay out children vertically in order.
	col : ColProps, List(Elem(a)) -> Elem(a)
	col = |props, children| Column({ children, props })

	## Present one modal surface, focus its first enabled control, trap keyboard
	## traversal inside it, and restore its opener after dismissal.
	dialog : DialogProps(a), List(Elem(a)) -> Elem(a)
	dialog = |props, children| Dialog({ children, props })

	## Group children in a labelled padded, bordered, rounded vertical surface.
	panel : PanelProps, List(Elem(a)) -> Elem(a)
	panel = |props, children| Panel({ children, props })

	## Constrain `child` to the available height and allow vertical scrolling.
	scroll : ScrollProps(a) -> Elem(a)
	scroll = |props| Scroll(props)

	## Present fixed-height rows while materializing only the visible native range.
	virtual_list : VirtualListProps(a) -> Elem(a)
	virtual_list = |props| if props.row_height == 0 or props.row_height > 16384 {
		crash "Gui virtual row height must be between 1 and 16384"
	} else {
		VirtualList(props)
	}

	## Adapt an already-built child tree to parent state.
	lift : Elem(child), (parent -> child), (parent, child -> parent) -> Elem(parent)
	lift = |elem, get_child, set_child| match elem {
		Text(value) => Text(value)
		Row(value) => Row({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Column(value) => Column({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Dialog(value) => {
			child_handler = value.props.on_dismiss
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Dialog({
				children: value.children.map(|child| lift(child, get_child, set_child)),
				props: DialogProps.{ label: value.props.label, on_dismiss: parent_handler!, gap: value.props.gap, padding: value.props.padding, width: value.props.width, height: value.props.height, grow: value.props.grow, bg: value.props.bg, hover_bg: value.props.hover_bg, active_bg: value.props.active_bg, fg: value.props.fg, border_color: value.props.border_color, border_width: value.props.border_width, radius: value.props.radius, font_size: value.props.font_size, overflow_x: value.props.overflow_x, overflow_y: value.props.overflow_y },
			})
		}
		Panel(value) => Panel({ props: value.props, children: value.children.map(|child| lift(child, get_child, set_child)) })
		Scroll(scroll_value) => Scroll(ScrollProps.{ axis: scroll_value.axis, content: lift(scroll_value.content, get_child, set_child), name: scroll_value.name })
		VirtualList(list_value) => VirtualList(
			VirtualListProps.{
				name: list_value.name,
				row_height: list_value.row_height,
				items: list_value.items.map(|item| { key: item.key, content: lift(item.content, get_child, set_child) }),
			},
		)
		ActionButton(button_value) => {
			child_handler = button_value.on_press
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			ActionButton(
				ActionButtonProps.{
					caption: button_value.caption,
					label: button_value.label,
					enabled: button_value.enabled,
					on_press: parent_handler!,
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
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Checkbox(
				CheckboxProps.{
					label: checkbox_value.label,
					checked: checkbox_value.checked,
					enabled: checkbox_value.enabled,
					on_change: parent_handler!,
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
		Textarea(textarea_value) => {
			child_handler = textarea_value.on_input
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Textarea(TextareaProps.{ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, on_input: parent_handler!, gap: textarea_value.gap, padding: textarea_value.padding, width: textarea_value.width, height: textarea_value.height, grow: textarea_value.grow, bg: textarea_value.bg, hover_bg: textarea_value.hover_bg, active_bg: textarea_value.active_bg, fg: textarea_value.fg, border_color: textarea_value.border_color, border_width: textarea_value.border_width, radius: textarea_value.radius, font_size: textarea_value.font_size, overflow_x: textarea_value.overflow_x, overflow_y: textarea_value.overflow_y })
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
		Textarea(TextareaProps(a)),
		Column({ children : List(Elem(a)), props : ColProps }),
		Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
		Panel({ children : List(Elem(a)), props : PanelProps }),
		Row({ children : List(Elem(a)), props : RowProps }),
		Scroll(ScrollProps(a)),
		VirtualList(VirtualListProps(a)),
		Text(Str),
	]
	inspect = |value| match value {
		Boundary(renderer) => Boundary(renderer)
		ActionButton(button_value) => ActionButton(button_value)
		Checkbox(checkbox_value) => Checkbox(checkbox_value)
		Textarea(textarea_value) => Textarea(textarea_value)
		Column(children) => Column(children)
		Dialog(dialog_value) => Dialog(dialog_value)
		Panel(children) => Panel(children)
		Row(children) => Row(children)
		Scroll(scroll_value) => Scroll(scroll_value)
		VirtualList(list_value) => VirtualList(list_value)
		Text(text_value) => Text(text_value)
	}
}
