import Action
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
	Image(ImageProps),
	Canvas(CanvasProps(a)),
	Column({ children : List(Elem(a)), props : ColProps }),
	Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
	Panel({ children : List(Elem(a)), props : PanelProps }),
	Row({ children : List(Elem(a)), props : RowProps }),
	Scroll(ScrollProps(a)),
	VirtualList(VirtualListProps(a)),
	TextInput(TextInputProps(a)),
	Text(Str),
].{

	## Properties for `col`. `label` is an optional stable semantic locator.
	## The remaining fields control the column's native layout and presentation.
	ColProps := {
		label : Str ?? "",
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for `row`. `label` is an optional stable semantic locator.
	## The remaining fields control the row's native layout and presentation.
	RowProps := {
		label : Str ?? "",
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for a modal dialog. `label` is its stable semantic name and
	## `on_dismiss` handles Escape. Dialogs center above an input-blocking scrim.
	DialogProps(a) := {
		label : Str,
		on_dismiss : (a, Event.Dismiss => Action(a)),
		gap : U32 ?? 16,
		padding : U32 ?? 24,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Px(520),
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x212f37),
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Rgb(0xeeeeea),
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 8,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for `panel`. Panels are padded, bordered, rounded vertical
	## surfaces by default, and carry a stable semantic `label`.
	PanelProps := {
		label : Str,
		gap : U32 ?? 8,
		padding : U32 ?? 16,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 8,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
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
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x315469),
		hover_bg : Gui.Color ?? Rgb(0x3e6a83),
		active_bg : Gui.Color ?? Rgb(0x274453),
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for a controlled single-line text field. `label` is its stable
	## semantic and accessibility name, `value` is authoritative application
	## state, and `placeholder` is an empty-field hint. Committed edits deliver
	## the complete value to `on_change`; Enter delivers it to `on_submit`.
	TextInputProps(a) := {
		label : Str,
		value : Str,
		placeholder : Str ?? "",
		enabled : Bool ?? True,
		on_change : (a, Event.TextChange => Action(a)),
		on_submit : (a, Event.TextSubmit => Action(a)),
		gap : U32 ?? 8,
		padding : U32 ?? 8,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Px(38),
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x162a33),
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Clip,
		overflow_y : Gui.Overflow ?? Clip,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
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
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
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
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Fill,
		height : Gui.Length ?? Px(160),
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0x10252b),
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 15,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Scroll,
		overflow_y : Gui.Overflow ?? Scroll,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Encoded image formats accepted by the native image decoder.
	ImageFormat : [Bmp, Gif, Jpeg, Png, Svg, Tiff, Webp]

	## How decoded pixels fit the image's styled bounds.
	ImageFit : [Contain, Cover, Fill, None, ScaleDown]

	## Properties for an encoded in-memory image. Bytes come from explicit
	## application data or a capability operation; the host never resolves a
	## path or URL. `label` is the stable semantic name.
	ImageProps := {
		label : Str,
		bytes : List(U8),
		format : ImageFormat,
		fit : ImageFit ?? Contain,
		grayscale : Bool ?? False,
		gap : U32 ?? 0,
		padding : U32 ?? 0,
		padding_top : Gui.Inset ?? Same,
		padding_right : Gui.Inset ?? Same,
		padding_bottom : Gui.Inset ?? Same,
		padding_left : Gui.Inset ?? Same,
		width : Gui.Length ?? Auto,
		height : Gui.Length ?? Auto,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Default,
		hover_bg : Gui.Color ?? Default,
		active_bg : Gui.Color ?? Default,
		disabled_bg : Gui.Color ?? Default,
		disabled_fg : Gui.Color ?? Default,
		focus_color : Gui.Color ?? Default,
		fg : Gui.Color ?? Default,
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Clip,
		overflow_y : Gui.Overflow ?? Clip,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## A retained drawing primitive. Keys must be non-zero and unique within a
	## canvas. Primitives are painted in list order and hit-tested in reverse.
	CanvasEllipse := { key : U64, label : Str, x : I32, y : I32, width : U32, height : U32, fill : Gui.Color, stroke : Gui.Color ?? Default, stroke_width : U32 ?? 0 }
	CanvasLine := { key : U64, label : Str, x1 : I32, y1 : I32, x2 : I32, y2 : I32, stroke : Gui.Color, stroke_width : U32 ?? 1 }
	CanvasRectangle := { key : U64, label : Str, x : I32, y : I32, width : U32, height : U32, fill : Gui.Color, stroke : Gui.Color ?? Default, stroke_width : U32 ?? 0, radius : U32 ?? 0 }
	CanvasPrimitive : [
		Ellipse(CanvasEllipse),
		Line(CanvasLine),
		Rectangle(CanvasRectangle),
	]

	## Properties for a native retained canvas. Coordinates are integer logical
	## pixels, which makes semantic gestures and deterministic rendering agree.
	CanvasProps(a) := {
		label : Str,
		primitives : List(CanvasPrimitive),
		on_pointer : (a, Event.CanvasPointer => Action(a)),
		width : Gui.Length ?? Fill,
		height : Gui.Length ?? Fill,
		min_width : Gui.Length ?? Auto,
		min_height : Gui.Length ?? Auto,
		max_width : Gui.Length ?? Auto,
		max_height : Gui.Length ?? Auto,
		grow : Bool ?? False,
		bg : Gui.Color ?? Rgb(0xffffff),
		border_color : Gui.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Gui.Inset ?? Same,
		border_right : Gui.Inset ?? Same,
		border_bottom : Gui.Inset ?? Same,
		border_left : Gui.Inset ?? Same,
		radius : U32 ?? 0,
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

	## Render encoded image bytes without granting the host ambient I/O.
	image : ImageProps -> Elem(a)
	image = |props| Image(props)

	## Paint keyed vector primitives and receive pointer gestures through one
	## captured direct-manipulation route.
	canvas : CanvasProps(a) -> Elem(a)
	canvas = |props| Canvas(props)

	## Display a controlled native single-line text editor.
	text_input : TextInputProps(a) -> Elem(a)
	text_input = |props| TextInput(props)

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
				props: DialogProps.{ label: value.props.label, on_dismiss: parent_handler!, gap: value.props.gap, padding: value.props.padding, padding_top: value.props.padding_top, padding_right: value.props.padding_right, padding_bottom: value.props.padding_bottom, padding_left: value.props.padding_left, width: value.props.width, height: value.props.height, min_width: value.props.min_width, min_height: value.props.min_height, max_width: value.props.max_width, max_height: value.props.max_height, grow: value.props.grow, bg: value.props.bg, hover_bg: value.props.hover_bg, active_bg: value.props.active_bg, disabled_bg: value.props.disabled_bg, disabled_fg: value.props.disabled_fg, focus_color: value.props.focus_color, fg: value.props.fg, border_color: value.props.border_color, border_width: value.props.border_width, border_top: value.props.border_top, border_right: value.props.border_right, border_bottom: value.props.border_bottom, border_left: value.props.border_left, radius: value.props.radius, font_size: value.props.font_size, font_weight: value.props.font_weight, text_overflow: value.props.text_overflow, overflow_x: value.props.overflow_x, overflow_y: value.props.overflow_y, align: value.props.align, justify: value.props.justify },
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
		TextInput(input_value) => {
			child_change = input_value.on_change
			child_submit = input_value.on_submit
			parent_change! = |parent, event| Action.lift(child_change(get_child(parent), event), parent, get_child, set_child)
			parent_submit! = |parent, event| Action.lift(child_submit(get_child(parent), event), parent, get_child, set_child)
			TextInput(TextInputProps.{ label: input_value.label, value: input_value.value, placeholder: input_value.placeholder, enabled: input_value.enabled, on_change: parent_change!, on_submit: parent_submit!, gap: input_value.gap, padding: input_value.padding, padding_top: input_value.padding_top, padding_right: input_value.padding_right, padding_bottom: input_value.padding_bottom, padding_left: input_value.padding_left, width: input_value.width, height: input_value.height, min_width: input_value.min_width, min_height: input_value.min_height, max_width: input_value.max_width, max_height: input_value.max_height, grow: input_value.grow, bg: input_value.bg, hover_bg: input_value.hover_bg, active_bg: input_value.active_bg, disabled_bg: input_value.disabled_bg, disabled_fg: input_value.disabled_fg, focus_color: input_value.focus_color, fg: input_value.fg, border_color: input_value.border_color, border_width: input_value.border_width, border_top: input_value.border_top, border_right: input_value.border_right, border_bottom: input_value.border_bottom, border_left: input_value.border_left, radius: input_value.radius, font_size: input_value.font_size, font_weight: input_value.font_weight, text_overflow: input_value.text_overflow, overflow_x: input_value.overflow_x, overflow_y: input_value.overflow_y, align: input_value.align, justify: input_value.justify })
		}
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
					padding_top: button_value.padding_top,
					padding_right: button_value.padding_right,
					padding_bottom: button_value.padding_bottom,
					padding_left: button_value.padding_left,
					width: button_value.width,
					height: button_value.height,
					min_width: button_value.min_width,
					min_height: button_value.min_height,
					max_width: button_value.max_width,
					max_height: button_value.max_height,
					grow: button_value.grow,
					bg: button_value.bg,
					hover_bg: button_value.hover_bg,
					active_bg: button_value.active_bg,
					disabled_bg: button_value.disabled_bg,
					disabled_fg: button_value.disabled_fg,
					focus_color: button_value.focus_color,
					fg: button_value.fg,
					border_color: button_value.border_color,
					border_width: button_value.border_width,
					border_top: button_value.border_top,
					border_right: button_value.border_right,
					border_bottom: button_value.border_bottom,
					border_left: button_value.border_left,
					radius: button_value.radius,
					font_size: button_value.font_size,
					font_weight: button_value.font_weight,
					text_overflow: button_value.text_overflow,
					overflow_x: button_value.overflow_x,
					overflow_y: button_value.overflow_y,
					align: button_value.align,
					justify: button_value.justify,
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
					padding_top: checkbox_value.padding_top,
					padding_right: checkbox_value.padding_right,
					padding_bottom: checkbox_value.padding_bottom,
					padding_left: checkbox_value.padding_left,
					width: checkbox_value.width,
					height: checkbox_value.height,
					min_width: checkbox_value.min_width,
					min_height: checkbox_value.min_height,
					max_width: checkbox_value.max_width,
					max_height: checkbox_value.max_height,
					grow: checkbox_value.grow,
					bg: checkbox_value.bg,
					hover_bg: checkbox_value.hover_bg,
					active_bg: checkbox_value.active_bg,
					disabled_bg: checkbox_value.disabled_bg,
					disabled_fg: checkbox_value.disabled_fg,
					focus_color: checkbox_value.focus_color,
					fg: checkbox_value.fg,
					border_color: checkbox_value.border_color,
					border_width: checkbox_value.border_width,
					border_top: checkbox_value.border_top,
					border_right: checkbox_value.border_right,
					border_bottom: checkbox_value.border_bottom,
					border_left: checkbox_value.border_left,
					radius: checkbox_value.radius,
					font_size: checkbox_value.font_size,
					font_weight: checkbox_value.font_weight,
					text_overflow: checkbox_value.text_overflow,
					overflow_x: checkbox_value.overflow_x,
					overflow_y: checkbox_value.overflow_y,
					align: checkbox_value.align,
					justify: checkbox_value.justify,
				},
			)
		}
		Textarea(textarea_value) => {
			child_handler = textarea_value.on_input
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Textarea(TextareaProps.{ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, on_input: parent_handler!, gap: textarea_value.gap, padding: textarea_value.padding, padding_top: textarea_value.padding_top, padding_right: textarea_value.padding_right, padding_bottom: textarea_value.padding_bottom, padding_left: textarea_value.padding_left, width: textarea_value.width, height: textarea_value.height, min_width: textarea_value.min_width, min_height: textarea_value.min_height, max_width: textarea_value.max_width, max_height: textarea_value.max_height, grow: textarea_value.grow, bg: textarea_value.bg, hover_bg: textarea_value.hover_bg, active_bg: textarea_value.active_bg, disabled_bg: textarea_value.disabled_bg, disabled_fg: textarea_value.disabled_fg, focus_color: textarea_value.focus_color, fg: textarea_value.fg, border_color: textarea_value.border_color, border_width: textarea_value.border_width, border_top: textarea_value.border_top, border_right: textarea_value.border_right, border_bottom: textarea_value.border_bottom, border_left: textarea_value.border_left, radius: textarea_value.radius, font_size: textarea_value.font_size, font_weight: textarea_value.font_weight, text_overflow: textarea_value.text_overflow, overflow_x: textarea_value.overflow_x, overflow_y: textarea_value.overflow_y, align: textarea_value.align, justify: textarea_value.justify })
		}
		Image(image_value) => Image(image_value)
		Canvas(canvas_value) => {
			child_handler = canvas_value.on_pointer
			parent_handler! = |parent, event| Action.lift(child_handler(get_child(parent), event), parent, get_child, set_child)
			Canvas(CanvasProps.{ label: canvas_value.label, primitives: canvas_value.primitives, on_pointer: parent_handler!, width: canvas_value.width, height: canvas_value.height, min_width: canvas_value.min_width, min_height: canvas_value.min_height, max_width: canvas_value.max_width, max_height: canvas_value.max_height, grow: canvas_value.grow, bg: canvas_value.bg, border_color: canvas_value.border_color, border_width: canvas_value.border_width, border_top: canvas_value.border_top, border_right: canvas_value.border_right, border_bottom: canvas_value.border_bottom, border_left: canvas_value.border_left, radius: canvas_value.radius })
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
		Image(ImageProps),
		Canvas(CanvasProps(a)),
		Column({ children : List(Elem(a)), props : ColProps }),
		Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
		Panel({ children : List(Elem(a)), props : PanelProps }),
		Row({ children : List(Elem(a)), props : RowProps }),
		Scroll(ScrollProps(a)),
		VirtualList(VirtualListProps(a)),
		TextInput(TextInputProps(a)),
		Text(Str),
	]
	inspect = |value| match value {
		Boundary(renderer) => Boundary(renderer)
		ActionButton(button_value) => ActionButton(button_value)
		Checkbox(checkbox_value) => Checkbox(checkbox_value)
		Textarea(textarea_value) => Textarea(textarea_value)
		Image(image_value) => Image(image_value)
		Canvas(canvas_value) => Canvas(canvas_value)
		Column(children) => Column(children)
		Dialog(dialog_value) => Dialog(dialog_value)
		Panel(children) => Panel(children)
		Row(children) => Row(children)
		Scroll(scroll_value) => Scroll(scroll_value)
		VirtualList(list_value) => VirtualList(list_value)
		TextInput(input_value) => TextInput(input_value)
		Text(text_value) => Text(text_value)
	}
}
