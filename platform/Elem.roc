import Action
import Event
import Host
import Key
import KeyedSeq
import Style
import Work

## A declarative UI tree whose event handlers transition application state `a`.
## Use `text`, `button`, `checkbox`, `row`, `col`, and `panel` to build a tree from
## property records, adjust an element afterwards with modifiers such as `padding`, and
## use `translate` or `lift` to embed UI over smaller component state.
Elem(a) :: [
	Component(BoundComponent(a)),
	ActionButton(ButtonNode(a)),
	Checkbox(CheckboxNode(a)),
	Textarea(TextareaNode(a)),
	Image(ImageNode),
	Canvas(CanvasNode(a)),
	Column({ children : List(Elem(a)), props : Frame }),
	KeyedColumn({ base_revision : U64, children : List(Elem(a)), full : Box({} => { children : List(Elem(a)), keys : List(Key) }), keys : List(Key), operations : List(KeyedOperation), props : Frame, revision : U64 }),
	Dialog({ children : List(Elem(a)), props : DialogNode(a) }),
	Popover({ children : List(Elem(a)), props : PopoverNode(a) }),
	Panel({ children : List(Elem(a)), props : PanelNode }),
	Row({ children : List(Elem(a)), props : Frame }),
	Scroll(ScrollNode(a)),
	VirtualList(VirtualListNode(a)),
	TextInput(TextInputNode(a)),
	StyledText(TextNode),
	Text(Str),
].{
	KeyedOperation : [KeyedInsert(Key, KeyedSeq.Placement), KeyedMove(Key, KeyedSeq.Placement), KeyedRemove(Key), KeyedSet(Key)]

	## Adapt a persistent keyed sequence into a native column. Every item is a
	## component boundary owned by its complete Key; item actions project by key,
	## so reordering never changes their target and removal cannot recreate one.
	KeyedColConfig(parent, item) := {
		key : Key,
		get : parent -> KeyedSeq(item),
		set : parent, KeyedSeq(item) -> parent,
		on_delegate : parent, Key -> Action(parent) ?? |parent, _key| Action.update(parent),
	}

	## Platform representation of a local boundary. Applications construct one
	## with `translate`, `translate_with`, or `try_translate`.
	BoundComponent(a) := {
		key : [None, Some(Key)],
		render : (a, (Elem(a) -> Work) -> Work),
		exists : (a, (Bool -> Work) -> Work),
		remember : [None, Some((a, (Box((a, (Bool -> Work) -> Work)) -> Work) -> Work))],
		## A transparent boundary renders on its own but holds no state of its
		## own: an action raised inside it belongs to the nearest boundary
		## above it that is not transparent.
		transparent : Bool,
	}

	## Connect a child renderer to parent state and give it a stable lifetime.
	## Start with `key`, `get`, and `set`; add policies only when needed.
	## `get` reads the child; `set` replaces it while preserving other parent data.
	## `on_delegate` receives the proposed parent and defaults to `Action.update`;
	## returning `Action.none` rejects the whole proposal. `memo` defaults to None.
	## A comparator receives saved and incoming child states: True promises that
	## both the rendered UI and captured handlers remain equivalent. Retaining
	## that comparison snapshot can require cloning during subsequent updates.
	TranslateConfig(parent, child) := {

		## Stable identity within the owner and container scope, independent of order.
		key : Key,

		## Read the child's state from the parent supplied by the platform.
		get : parent -> child,

		## Replace that child while preserving unrelated parent state.
		set : parent, child -> parent,

		## Decide whether to accept a proposed parent containing the child's change.
		## `Action.none` rejects the entire proposal. The default accepts it.
		on_delegate : parent -> Action(parent) ?? Action.update,

		## Compare saved and incoming child states. True promises equivalent UI and
		## captured handlers. Keeping the comparison snapshot can require cloning.
		memo : [None, Some((child, child -> Bool))] ?? None,
	}

	## Connect a removable child by stable identity, not a captured list position.
	## Omit the element when the child is already absent.
	## `get` and `set` return `Err(Removed)` when the projection no longer exists.
	## A rejected setter discards the whole action before delegation or task launch.
	## Preserve unrelated parent data and never recreate a removed child in `set`.
	## `on_delegate` and `memo` follow the same contracts as TranslateConfig.
	TryTranslateConfig(parent, child) := {

		## Stable identity for this logical child within its owner and container.
		key : Key,

		## Read the child, or return `Err(Removed)` if it no longer exists.
		get : parent -> Try(child, [Removed]),

		## Replace an existing child, preserving other data. `Err(Removed)` rejects
		## the whole action before delegation or task launch; do not recreate it.
		set : parent, child -> Try(parent, [Removed]),

		## Handle the proposed parent after a successful setter; defaults to acceptance.
		on_delegate : parent -> Action(parent) ?? Action.update,

		## Optional saved/incoming comparison, with the same contract as TranslateConfig.
		memo : [None, Some((child, child -> Bool))] ?? None,
	}

	## Embed a renderer over a smaller part of parent state. Local updates render
	## this child without rebuilding siblings. `get` reads it; `set` replaces it.
	## Reconstructing
	## this unkeyed descriptor from its parent starts a fresh mounted lifetime.
	translate : (child -> Elem(child)), (parent -> child), (parent, child -> parent) -> Elem(parent)
	translate = |render, get, set| boundary(render, None, |parent, done| Work.get(|| done(Ok(get(parent)))), |parent, child| Ok(set(parent, child)), Action.update, None)

	## Preserve a child's lifetime across parent renders and reordering using a key.
	## Use this when tasks or native interaction state should survive those renders.
	## Keys preserve the lifetime within the surviving owner and native scope.
	## Memoization is opt-in; its input must cover rendering and handler captures.
	translate_with : (child -> Elem(child)), TranslateConfig(parent, child) -> Elem(parent)
	translate_with = |render, TranslateConfig.(config)| boundary(render, Some(config.key), |parent, done| Work.get(|| done(Ok((config.get)(parent)))), |parent, child| Ok((config.set)(parent, child)), config.on_delegate, config.memo)

	## Embed a removable collection entry using a stable key and fallible adapters.
	## Missing projections discard task completions and cannot recreate state.
	try_translate : (child -> Elem(child)), TryTranslateConfig(parent, child) -> Elem(parent)
	try_translate = |render, TryTranslateConfig.(config)| {
		project = |parent, done| Work.get(|| done((config.get)(parent)))
		boundary(render, Some(config.key), project, config.set, config.on_delegate, config.memo)
	}

	Project(parent, child) : (parent, (Try(child, [Removed]) -> Work) -> Work)

	boundary : (child -> Elem(child)), [None, Some(Key)], Project(parent, child), (parent, child -> Try(parent, [Removed])), (parent -> Action(parent)), [None, Some((child, child -> Bool))] -> Elem(parent)
	boundary = |render, key, project, set, delegated, memo| {
		adapt = |action, latest, done| Action.adapt_work!(action, latest, project, set, Some(delegated), done)
		remember = match memo {
			None => None
			Some(compare) => Some(
				|parent, captured| Work.next(
					|| project(
						parent,
						|result| match result {
							Err(Removed) => crash "cannot remember a removed boundary"
							Ok(previous) => {
								Work.next(|| captured(Box.box(|next, compared| snapshot_test(project, compare, previous, next, compared))))
							}
						},
					),
				),
			)
		}
		render_boundary = |parent, done| project(
			parent,
			|result| match result {
				Err(Removed) => crash "render emitted a removed component"
				Ok(child) => done(lift_with(render(child), project, set, adapt))
			},
		)
		exists = |parent, done| project(
			parent,
			|result| done(
				match result {
					Ok(_) => True
					Err(Removed) => False
				},
			),
		)
		Component(BoundComponent.{ key, render: render_boundary, exists: exists, remember, transparent: False })
	}

	## The semantic locator and presentation shared by `row`, `col`, and
	## `keyed_col`.
	Frame := { label : Str, style : Style }

	## Platform representation of a modal dialog.
	DialogNode(a) := { label : Str, style : Style, on_dismiss : (a, Event.Dismiss => Action(a)) }

	## Where a popover's surface sits against its anchor: over it, under it,
	## before it, or after it. The surface moves to the opposite side when the
	## window has no room for it on the one asked for.
	Placement : [Above, Below, Start, End]

	## Platform representation of a popover. Its first child is the anchor and
	## any others are the surface's content. A popover with no content is a
	## hover region: it reports the pointer entering and leaving its anchor
	## and presents nothing.
	PopoverNode(a) := {
		label : Str,
		placement : Placement,
		delay_ms : U32,
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))],
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))],
		style : Style,
	}

	## Platform representation of a headed surface.
	PanelNode := { label : Str, style : Style, heading : Str, heading_size : U32, heading_weight : U32, heading_color : Style.Color }

	## Platform representation of a button. `caption` is its visible text and
	## `label` is its stable semantic locator.
	ButtonNode(a) := {
		caption : Str,
		label : Str,
		enabled : Bool,
		on_press : (a, Event.Press => Action(a)),
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))],
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))],
		style : Style,
	}

	## Platform representation of a single-line text editor.
	TextInputNode(a) := {
		label : Str,
		value : Str,
		placeholder : Str,
		enabled : Bool,
		on_change : (a, Event.TextChange => Action(a)),
		on_submit : (a, Event.TextSubmit => Action(a)),
		style : Style,
	}

	## The axes a scroll region moves along.
	ScrollAxis : [Both, Horizontal, Vertical]

	## Platform representation of a scrollable region.
	ScrollNode(a) := { axis : ScrollAxis, content : Elem(a), label : Str, style : Style }

	## One stable row in a virtual list. `key` identifies the row independently
	## of its current index, while `content` is an ordinary element tree.
	VirtualListItem(a) := { content : Elem(a), key : U64 }

	## Platform representation of a viewport-driven, fixed-height list. A list
	## built by `virtual_list` carries its rows in `items`; one built by
	## `virtual_rows` carries a `provider` instead and no items.
	VirtualListNode(a) := { items : List(VirtualListItem(a)), label : Str, row_height : U32, row_gap : U32, style : Style, provider : [None, Some(RowProvider(a))] }

	## Where a list places a row it is asked to bring into view: at the leading
	## edge, in the middle, at the trailing edge, or wherever moves it least —
	## not at all when the row is already in view.
	RowAlign : [Start, Center, End, Nearest]

	## A request to bring `row` into view at `align`. The list moves once for
	## each distinct `serial`: holding the same request across later renders
	## leaves a person's own scrolling alone, and a new serial moves the list
	## again, even to the same row.
	ScrollRequest : { row : U64, align : RowAlign, serial : U64 }

	## Platform representation of rows produced on demand.
	RowProvider(a) := {
		count : U64,
		render_row : U64 -> Elem(a),
		row_key : U64 -> U64,
		scroll_to : [None, Some(ScrollRequest)],
		on_range : [None, Some((a, Event.VisibleRows => Action(a)))],
	}

	## Platform representation of a checkbox.
	CheckboxNode(a) := {
		label : Str,
		checked : Bool,
		enabled : Bool,
		on_change : (a, Event.Check => Action(a)),
		box_bg : Style.Color,
		box_checked_bg : Style.Color,
		box_border : Style.Color,
		mark_color : Style.Color,
		style : Style,
	}

	## Platform representation of a multiline text editor.
	TextareaNode(a) := {
		label : Str,
		value : Str,
		placeholder : Str,
		enabled : Bool,
		read_only : Bool,
		on_input : (a, Event.Input => Action(a)),
		style : Style,
	}

	## Encoded image formats accepted by the native image decoder.
	ImageFormat : [Bmp, Gif, Jpeg, Png, Svg, Tiff, Webp]

	## How decoded pixels fit the image's styled bounds.
	ImageFit : [Contain, Cover, Fill, None, ScaleDown]

	## Platform representation of an encoded in-memory image.
	ImageNode := { label : Str, bytes : List(U8), format : ImageFormat, fit : ImageFit, grayscale : Bool, style : Style }

	## A retained drawing primitive. Keys must be non-zero and unique within a
	## canvas. Primitives are painted in list order and hit-tested in reverse.
	CanvasEllipse := { key : U64, label : Str, x : I32, y : I32, width : U32, height : U32, fill : Style.Color, stroke : Style.Color ?? Default, stroke_width : U32 ?? 0 }
	CanvasLine := { key : U64, label : Str, x1 : I32, y1 : I32, x2 : I32, y2 : I32, stroke : Style.Color, stroke_width : U32 ?? 1 }
	CanvasRectangle := { key : U64, label : Str, x : I32, y : I32, width : U32, height : U32, fill : Style.Color, stroke : Style.Color ?? Default, stroke_width : U32 ?? 0, radius : U32 ?? 0 }
	CanvasPrimitive : [
		Ellipse(CanvasEllipse),
		Line(CanvasLine),
		Rectangle(CanvasRectangle),
	]

	## A filled, optionally stroked and rounded rectangle on a canvas.
	rectangle : CanvasRectangle -> CanvasPrimitive
	rectangle = |shape| Rectangle(shape)

	## A filled, optionally stroked ellipse on a canvas.
	ellipse : CanvasEllipse -> CanvasPrimitive
	ellipse = |shape| Ellipse(shape)

	## A stroked line on a canvas.
	line : CanvasLine -> CanvasPrimitive
	line = |shape| Line(shape)

	## Platform representation of a native retained canvas. Coordinates are
	## integer logical pixels, which makes semantic gestures and deterministic
	## rendering agree.
	CanvasNode(a) := { label : Str, primitives : List(CanvasPrimitive), on_pointer : (a, Event.CanvasPointer => Action(a)), style : Style }

	## Platform representation of text set in its own colour, size, weight, and
	## face. Only the typographic fields of `style` apply to a string.
	TextNode := { value : Str, style : Style }

	## Properties for `col`. `label` is an optional stable semantic locator.
	## The remaining fields control the column's native layout and presentation.
	ColProps := {
		label : Str ?? "",
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for `row`. `label` is an optional stable semantic locator.
	## The remaining fields control the row's native layout and presentation.
	RowProps := {
		label : Str ?? "",
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for a modal dialog. `label` is its stable semantic name and
	## `on_dismiss` handles Escape. Dialogs center above an input-blocking scrim.
	DialogProps(a) := {
		label : Str,
		on_dismiss : (a, Event.Dismiss => Action(a)),
		gap : U32 ?? 16,
		padding : U32 ?? 24,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Px(520),
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0x212f37),
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Rgb(0xeeeeea),
		border_color : Style.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 8,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for `popover`. `label` is the surface's stable semantic name,
	## its locator as a tooltip. The surface opens `delay_ms` after the pointer
	## comes to rest on the anchor, and at once when keyboard focus enters the
	## anchor; it closes when both have left, or on Escape. The style fields
	## dress the surface, never the anchor.
	PopoverProps(a) := {
		label : Str,
		placement : Placement ?? Below,
		delay_ms : U32 ?? 500,

		## Optional pointer transitions on the anchor; absent handlers allocate
		## no event routes.
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		gap : U32 ?? 4,
		padding : U32 ?? 8,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Px(360),
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0x0f1b21),
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Rgb(0xeeeeea),
		border_color : Style.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 14,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 12,
		shadow_y : U32 ?? 4,
		shadow_color : Style.Color ?? Rgb(0x000000),
		shadow_alpha : U32 ?? 60,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for `panel`. Panels are padded, bordered, rounded vertical
	## surfaces by default, and carry a stable semantic `label`.
	PanelProps := {
		label : Str,

		## The panel's own visible heading, distinct from `label`, which stays a
		## semantic locator. An empty heading paints none. `heading_size`,
		## `heading_weight`, and `heading_color` set it apart from the panel's
		## body text; each zero or `Default` keeps the panel's own.
		heading : Str ?? "",
		heading_size : U32 ?? 0,
		heading_weight : U32 ?? 0,
		heading_color : Style.Color ?? Default,
		gap : U32 ?? 8,
		padding : U32 ?? 16,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 8,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for `action_button`. `caption` is visible text and `label` is
	## its stable semantic name. Disabled buttons remain visible but cannot be
	## focused or dispatch presses. Visual fields use the same native style
	## vocabulary as layout controls.
	ButtonProps(a) := {
		caption : Str,
		label : Str,
		enabled : Bool ?? True,
		on_press : (a, Event.Press => Action(a)),

		## Optional pointer transitions; absent handlers allocate no event routes.
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		gap : U32 ?? 8,
		padding : U32 ?? 8,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0x315469),
		hover_bg : Style.Color ?? Rgb(0x3e6a83),
		active_bg : Style.Color ?? Rgb(0x274453),
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
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
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Px(38),
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0x162a33),
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Clip,
		overflow_y : Style.Overflow ?? Clip,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	ScrollProps(a) := {
		axis : ScrollAxis ?? Vertical,
		content : Elem(a),
		label : Str,
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for a viewport-driven, fixed-height list. Only rows intersecting
	## the native viewport are materialized as GPUI elements.
	VirtualListProps(a) := {
		items : List(VirtualListItem(a)),
		label : Str,
		row_height : U32,

		## The space held clear at the bottom of each row inside `row_height`,
		## so rows read as separate surfaces rather than one continuous block.
		row_gap : U32 ?? 0,
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for a fixed-height list of `count` rows produced on demand.
	## `render_row` is called only for the rows near the viewport, so the cost
	## of a render follows the rows on screen rather than `count`.
	VirtualRowsProps(a) := {
		label : Str,
		row_height : U32,

		## How many rows the list holds. The list scrolls through all of them.
		count : U64,

		## Build the row at a zero-based index below `count`.
		render_row : U64 -> Elem(a),

		## The row's stable identity, unique among the rows shown together.
		## The index is the default; a key drawn from the data keeps a row's
		## native state with its data when rows are inserted above it.
		row_key : U64 -> U64 ?? |index| index,

		## Bring a row into view. See `ScrollRequest`.
		scroll_to : [None, Some(ScrollRequest)] ?? None,

		## Receive the rows intersecting the viewport whenever they change.
		on_range : [None, Some((a, Event.VisibleRows => Action(a)))] ?? None,
		row_gap : U32 ?? 0,
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for `checkbox`. `label` is both visible text and the stable
	## semantic name used by specifications. `on_change` receives the requested
	## checked state. The common visual fields mirror `Style.Style`; defaults let a
	## record literal name only the properties it changes.
	CheckboxProps(a) := {
		label : Str,
		checked : Bool,
		enabled : Bool ?? True,
		on_change : (a, Event.Check => Action(a)),

		## The indicator's own colours. `fg` reaches the caption; these reach the
		## box and its mark, which otherwise keep host values chosen for a dark
		## ground. Each defaults to the host's own.
		box_bg : Style.Color ?? Default,
		box_checked_bg : Style.Color ?? Default,
		box_border : Style.Color ?? Default,
		mark_color : Style.Color ?? Default,
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Visible,
		overflow_y : Style.Overflow ?? Visible,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
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
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Fill,
		height : Style.Length ?? Px(160),
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0x10252b),
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Rgb(0x48666b),
		border_width : U32 ?? 1,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 6,
		font_size : U32 ?? 15,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Scroll,
		overflow_y : Style.Overflow ?? Scroll,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

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
		padding_top : Style.Inset ?? Same,
		padding_right : Style.Inset ?? Same,
		padding_bottom : Style.Inset ?? Same,
		padding_left : Style.Inset ?? Same,
		width : Style.Length ?? Auto,
		height : Style.Length ?? Auto,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Default,
		hover_bg : Style.Color ?? Default,
		active_bg : Style.Color ?? Default,
		disabled_bg : Style.Color ?? Default,
		disabled_fg : Style.Color ?? Default,
		focus_color : Style.Color ?? Default,
		fg : Style.Color ?? Default,
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Style.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Style.FontFace ?? Default,
		text_overflow : Style.TextOverflow ?? Wrap,
		overflow_x : Style.Overflow ?? Clip,
		overflow_y : Style.Overflow ?? Clip,
		align : Style.Align ?? Default,
		justify : Style.Justify ?? Default,
	}

	## Properties for a native retained canvas. Coordinates are integer logical
	## pixels, which makes semantic gestures and deterministic rendering agree.
	CanvasProps(a) := {
		label : Str,
		primitives : List(CanvasPrimitive),
		on_pointer : (a, Event.CanvasPointer => Action(a)),
		width : Style.Length ?? Fill,
		height : Style.Length ?? Fill,
		min_width : Style.Length ?? Auto,
		min_height : Style.Length ?? Auto,
		max_width : Style.Length ?? Auto,
		max_height : Style.Length ?? Auto,
		grow : Bool ?? False,
		bg : Style.Color ?? Rgb(0xffffff),
		border_color : Style.Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Style.Inset ?? Same,
		border_right : Style.Inset ?? Same,
		border_bottom : Style.Inset ?? Same,
		border_left : Style.Inset ?? Same,
		radius : U32 ?? 0,
	}

	## Properties for `styled_text`. A string is the only thing a typographic
	## step is about, so these are the type fields alone: a typographic step
	## costs no container, and none of a container's layout is implied.
	TextProps := {
		value : Str,
		fg : Style.Color ?? Default,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		font_face : Style.FontFace ?? Default,
	}

	# The presentation fields every element property record shares.
	style_of = |props| Style.{
		gap: props.gap,
		padding: props.padding,
		padding_top: props.padding_top,
		padding_right: props.padding_right,
		padding_bottom: props.padding_bottom,
		padding_left: props.padding_left,
		width: props.width,
		height: props.height,
		min_width: props.min_width,
		min_height: props.min_height,
		max_width: props.max_width,
		max_height: props.max_height,
		grow: props.grow,
		bg: props.bg,
		hover_bg: props.hover_bg,
		active_bg: props.active_bg,
		disabled_bg: props.disabled_bg,
		disabled_fg: props.disabled_fg,
		focus_color: props.focus_color,
		fg: props.fg,
		border_color: props.border_color,
		border_width: props.border_width,
		border_top: props.border_top,
		border_right: props.border_right,
		border_bottom: props.border_bottom,
		border_left: props.border_left,
		radius: props.radius,
		font_size: props.font_size,
		font_weight: props.font_weight,
		shadow: props.shadow,
		shadow_y: props.shadow_y,
		shadow_color: props.shadow_color,
		shadow_alpha: props.shadow_alpha,
		font_face: props.font_face,
		text_overflow: props.text_overflow,
		overflow_x: props.overflow_x,
		overflow_y: props.overflow_y,
		align: props.align,
		justify: props.justify,
	}

	## Display literal text. It inherits colour and size from its container.
	text : Str -> Elem(a)
	text = |value| Text(value)

	## Display text in its own colour, size, weight, and face, without a
	## container element that exists only to carry them.
	styled_text : TextProps -> Elem(a)
	styled_text = |props| StyledText({ value: props.value, style: Style.{ fg: props.fg, font_size: props.font_size, font_weight: props.font_weight, font_face: props.font_face } })

	## Display a controlled button. `caption` is its visible text and `label`
	## is its stable semantic locator.
	button : ButtonProps(a) -> Elem(a)
	button = |props| ActionButton({ caption: props.caption, label: props.label, enabled: props.enabled, on_press: props.on_press, on_hover_enter: props.on_hover_enter, on_hover_exit: props.on_hover_exit, style: style_of(props) })

	## Display a controlled checkbox. A handler must return the state containing
	## the next `checked` value for the visual state to change.
	checkbox : CheckboxProps(a) -> Elem(a)
	checkbox = |props| Checkbox({
		label: props.label,
		checked: props.checked,
		enabled: props.enabled,
		on_change: props.on_change,
		box_bg: props.box_bg,
		box_checked_bg: props.box_checked_bg,
		box_border: props.box_border,
		mark_color: props.mark_color,
		style: style_of(props),
	})

	## Edit controlled multiline text. The application installs the next value
	## returned by `on_input`; use `read_only: True` for response viewers.
	textarea : TextareaProps(a) -> Elem(a)
	textarea = |props| Textarea({ label: props.label, value: props.value, placeholder: props.placeholder, enabled: props.enabled, read_only: props.read_only, on_input: props.on_input, style: style_of(props) })

	## Render encoded image bytes without granting the host ambient I/O.
	image : ImageProps -> Elem(a)
	image = |props| Image({ label: props.label, bytes: props.bytes, format: props.format, fit: props.fit, grayscale: props.grayscale, style: style_of(props) })

	## Paint keyed vector primitives and receive pointer gestures through one
	## captured direct-manipulation route.
	canvas : CanvasProps(a) -> Elem(a)
	canvas = |props| Canvas({
		label: props.label,
		primitives: props.primitives,
		on_pointer: props.on_pointer,
		style: Style.{
			width: props.width,
			height: props.height,
			min_width: props.min_width,
			min_height: props.min_height,
			max_width: props.max_width,
			max_height: props.max_height,
			grow: props.grow,
			bg: props.bg,
			border_color: props.border_color,
			border_width: props.border_width,
			border_top: props.border_top,
			border_right: props.border_right,
			border_bottom: props.border_bottom,
			border_left: props.border_left,
			radius: props.radius,
		},
	})

	## Display a controlled native single-line text editor.
	text_input : TextInputProps(a) -> Elem(a)
	text_input = |props| TextInput({ label: props.label, value: props.value, placeholder: props.placeholder, enabled: props.enabled, on_change: props.on_change, on_submit: props.on_submit, style: style_of(props) })

	## Lay out children horizontally in order.
	row : RowProps, List(Elem(a)) -> Elem(a)
	row = |props, children| Row({ children, props: { label: props.label, style: style_of(props) } })

	## Lay out children vertically in order.
	col : ColProps, List(Elem(a)) -> Elem(a)
	col = |props, children| Column({ children, props: { label: props.label, style: style_of(props) } })

	## Apply a presentation change to an element. Literal text becomes styled
	## text, and a component boundary passes the change to the root it renders.
	with_style : Elem(a), (Style -> Style) -> Elem(a)
	with_style = |elem, change| match elem {
		Text(value) => StyledText({ value, style: change(Style.{}) })
		StyledText(value) => StyledText({ ..value, style: change(value.style) })
		Row(value) => Row({ ..value, props: { ..value.props, style: change(value.props.style) } })
		Column(value) => Column({ ..value, props: { ..value.props, style: change(value.props.style) } })
		KeyedColumn(value) => KeyedColumn({ ..value, props: { ..value.props, style: change(value.props.style) } })
		Dialog(value) => Dialog({ ..value, props: { ..value.props, style: change(value.props.style) } })
		Popover(value) => Popover({ ..value, children: map_anchor(value.children, |anchor| with_style(anchor, change)) })
		Panel(value) => Panel({ ..value, props: { ..value.props, style: change(value.props.style) } })
		ActionButton(value) => ActionButton({ ..value, style: change(value.style) })
		Checkbox(value) => Checkbox({ ..value, style: change(value.style) })
		Textarea(value) => Textarea({ ..value, style: change(value.style) })
		Image(value) => Image({ ..value, style: change(value.style) })
		Canvas(value) => Canvas({ ..value, style: change(value.style) })
		Scroll(value) => Scroll({ ..value, style: change(value.style) })
		VirtualList(value) => VirtualList({ ..value, style: change(value.style) })
		TextInput(value) => TextInput({ ..value, style: change(value.style) })
		Component(bound) => through_boundary(bound, |rendered| with_style(rendered, change))
	}

	# A modifier on a popover applies to its anchor, the element it annotates;
	# the popover itself is configured by its props.
	map_anchor : List(Elem(a)), (Elem(a) -> Elem(a)) -> List(Elem(a))
	map_anchor = |children, change| match children.first() {
		Ok(anchor) => [change(anchor)].concat(children.drop_first(1))
		Err(_) => children
	}

	# A modifier on a boundary applies to whatever that boundary renders.
	through_boundary : BoundComponent(a), (Elem(a) -> Elem(a)) -> Elem(a)
	through_boundary = |bound, change| {
		child_render = bound.render
		Component({ ..bound, render: |state, done| child_render(state, |rendered| done(change(rendered))) })
	}

	## Name an element with a stable semantic locator for specifications and
	## accessibility. Literal text has none.
	label : Elem(a), Str -> Elem(a)
	label = |elem, name| match elem {
		Row(value) => Row({ ..value, props: { ..value.props, label: name } })
		Column(value) => Column({ ..value, props: { ..value.props, label: name } })
		KeyedColumn(value) => KeyedColumn({ ..value, props: { ..value.props, label: name } })
		Dialog(value) => Dialog({ ..value, props: { ..value.props, label: name } })
		Popover(value) => Popover({ ..value, children: map_anchor(value.children, |anchor| label(anchor, name)) })
		Panel(value) => Panel({ ..value, props: { ..value.props, label: name } })
		ActionButton(value) => ActionButton({ ..value, label: name })
		Checkbox(value) => Checkbox({ ..value, label: name })
		Textarea(value) => Textarea({ ..value, label: name })
		Image(value) => Image({ ..value, label: name })
		Canvas(value) => Canvas({ ..value, label: name })
		Scroll(value) => Scroll({ ..value, label: name })
		VirtualList(value) => VirtualList({ ..value, label: name })
		TextInput(value) => TextInput({ ..value, label: name })
		Component(bound) => through_boundary(bound, |rendered| label(rendered, name))
		_ => elem
	}

	## Space between a container's children.
	gap : Elem(a), U32 -> Elem(a)
	gap = |elem, value| with_style(elem, |style| { ..style, gap: value })

	## Inset on every side that has no side of its own.
	padding : Elem(a), U32 -> Elem(a)
	padding = |elem, value| with_style(elem, |style| { ..style, padding: value })

	padding_top : Elem(a), Style.Inset -> Elem(a)
	padding_top = |elem, value| with_style(elem, |style| { ..style, padding_top: value })

	padding_right : Elem(a), Style.Inset -> Elem(a)
	padding_right = |elem, value| with_style(elem, |style| { ..style, padding_right: value })

	padding_bottom : Elem(a), Style.Inset -> Elem(a)
	padding_bottom = |elem, value| with_style(elem, |style| { ..style, padding_bottom: value })

	padding_left : Elem(a), Style.Inset -> Elem(a)
	padding_left = |elem, value| with_style(elem, |style| { ..style, padding_left: value })

	## The element's width.
	width : Elem(a), Style.Length -> Elem(a)
	width = |elem, value| with_style(elem, |style| { ..style, width: value })

	## The element's height.
	height : Elem(a), Style.Length -> Elem(a)
	height = |elem, value| with_style(elem, |style| { ..style, height: value })

	min_width : Elem(a), Style.Length -> Elem(a)
	min_width = |elem, value| with_style(elem, |style| { ..style, min_width: value })

	min_height : Elem(a), Style.Length -> Elem(a)
	min_height = |elem, value| with_style(elem, |style| { ..style, min_height: value })

	max_width : Elem(a), Style.Length -> Elem(a)
	max_width = |elem, value| with_style(elem, |style| { ..style, max_width: value })

	max_height : Elem(a), Style.Length -> Elem(a)
	max_height = |elem, value| with_style(elem, |style| { ..style, max_height: value })

	## Take the space left over along the parent's layout axis.
	grow : Elem(a), Bool -> Elem(a)
	grow = |elem, value| with_style(elem, |style| { ..style, grow: value })

	## The background colour.
	bg : Elem(a), Style.Color -> Elem(a)
	bg = |elem, value| with_style(elem, |style| { ..style, bg: value })

	## The background while the pointer is over the element.
	hover_bg : Elem(a), Style.Color -> Elem(a)
	hover_bg = |elem, value| with_style(elem, |style| { ..style, hover_bg: value })

	## The background while the element is pressed.
	active_bg : Elem(a), Style.Color -> Elem(a)
	active_bg = |elem, value| with_style(elem, |style| { ..style, active_bg: value })

	disabled_bg : Elem(a), Style.Color -> Elem(a)
	disabled_bg = |elem, value| with_style(elem, |style| { ..style, disabled_bg: value })

	disabled_fg : Elem(a), Style.Color -> Elem(a)
	disabled_fg = |elem, value| with_style(elem, |style| { ..style, disabled_fg: value })

	focus_color : Elem(a), Style.Color -> Elem(a)
	focus_color = |elem, value| with_style(elem, |style| { ..style, focus_color: value })

	## The text colour.
	fg : Elem(a), Style.Color -> Elem(a)
	fg = |elem, value| with_style(elem, |style| { ..style, fg: value })

	border_color : Elem(a), Style.Color -> Elem(a)
	border_color = |elem, value| with_style(elem, |style| { ..style, border_color: value })

	border_width : Elem(a), U32 -> Elem(a)
	border_width = |elem, value| with_style(elem, |style| { ..style, border_width: value })

	border_top : Elem(a), Style.Inset -> Elem(a)
	border_top = |elem, value| with_style(elem, |style| { ..style, border_top: value })

	border_right : Elem(a), Style.Inset -> Elem(a)
	border_right = |elem, value| with_style(elem, |style| { ..style, border_right: value })

	border_bottom : Elem(a), Style.Inset -> Elem(a)
	border_bottom = |elem, value| with_style(elem, |style| { ..style, border_bottom: value })

	border_left : Elem(a), Style.Inset -> Elem(a)
	border_left = |elem, value| with_style(elem, |style| { ..style, border_left: value })

	## The corner radius.
	radius : Elem(a), U32 -> Elem(a)
	radius = |elem, value| with_style(elem, |style| { ..style, radius: value })

	## The text size; zero selects the native default.
	font_size : Elem(a), U32 -> Elem(a)
	font_size = |elem, value| with_style(elem, |style| { ..style, font_size: value })

	## The text weight, 100 through 900; zero selects the native default.
	font_weight : Elem(a), U32 -> Elem(a)
	font_weight = |elem, value| with_style(elem, |style| { ..style, font_weight: value })

	## The blur radius of a soft drop shadow; zero paints none.
	shadow : Elem(a), U32 -> Elem(a)
	shadow = |elem, value| with_style(elem, |style| { ..style, shadow: value })

	shadow_y : Elem(a), U32 -> Elem(a)
	shadow_y = |elem, value| with_style(elem, |style| { ..style, shadow_y: value })

	shadow_color : Elem(a), Style.Color -> Elem(a)
	shadow_color = |elem, value| with_style(elem, |style| { ..style, shadow_color: value })

	shadow_alpha : Elem(a), U32 -> Elem(a)
	shadow_alpha = |elem, value| with_style(elem, |style| { ..style, shadow_alpha: value })

	font_face : Elem(a), Style.FontFace -> Elem(a)
	font_face = |elem, value| with_style(elem, |style| { ..style, font_face: value })

	text_overflow : Elem(a), Style.TextOverflow -> Elem(a)
	text_overflow = |elem, value| with_style(elem, |style| { ..style, text_overflow: value })

	overflow_x : Elem(a), Style.Overflow -> Elem(a)
	overflow_x = |elem, value| with_style(elem, |style| { ..style, overflow_x: value })

	overflow_y : Elem(a), Style.Overflow -> Elem(a)
	overflow_y = |elem, value| with_style(elem, |style| { ..style, overflow_y: value })

	## Where a container places its children across its layout axis.
	align : Elem(a), Style.Align -> Elem(a)
	align = |elem, value| with_style(elem, |style| { ..style, align: value })

	## How a container distributes its children along its layout axis.
	justify : Elem(a), Style.Justify -> Elem(a)
	justify = |elem, value| with_style(elem, |style| { ..style, justify: value })

	## Whether a button, checkbox, text input, or textarea accepts interaction.
	enabled : Elem(a), Bool -> Elem(a)
	enabled = |elem, value| match elem {
		ActionButton(props) => ActionButton({ ..props, enabled: value })
		Checkbox(props) => Checkbox({ ..props, enabled: value })
		TextInput(props) => TextInput({ ..props, enabled: value })
		Textarea(props) => Textarea({ ..props, enabled: value })
		Component(bound) => through_boundary(bound, |rendered| enabled(rendered, value))
		_ => elem
	}

	## Text shown by an empty text input or textarea.
	placeholder : Elem(a), Str -> Elem(a)
	placeholder = |elem, value| match elem {
		TextInput(props) => TextInput({ ..props, placeholder: value })
		Textarea(props) => Textarea({ ..props, placeholder: value })
		Component(bound) => through_boundary(bound, |rendered| placeholder(rendered, value))
		_ => elem
	}

	## Let a textarea be selected and scrolled but not edited.
	read_only : Elem(a), Bool -> Elem(a)
	read_only = |elem, value| match elem {
		Textarea(props) => Textarea({ ..props, read_only: value })
		Component(bound) => through_boundary(bound, |rendered| read_only(rendered, value))
		_ => elem
	}

	## The axes a scroll region moves along.
	axis : Elem(a), ScrollAxis -> Elem(a)
	axis = |elem, value| match elem {
		Scroll(props) => Scroll({ ..props, axis: value })
		Component(bound) => through_boundary(bound, |rendered| axis(rendered, value))
		_ => elem
	}

	## Space held clear at the bottom of each virtual list row inside its row height.
	row_gap : Elem(a), U32 -> Elem(a)
	row_gap = |elem, value| match elem {
		VirtualList(props) => VirtualList({ ..props, row_gap: value })
		Component(bound) => through_boundary(bound, |rendered| row_gap(rendered, value))
		_ => elem
	}

	## How an image's decoded pixels fit its styled bounds.
	fit : Elem(a), ImageFit -> Elem(a)
	fit = |elem, value| match elem {
		Image(props) => Image({ ..props, fit: value })
		Component(bound) => through_boundary(bound, |rendered| fit(rendered, value))
		_ => elem
	}

	## Paint an image without colour.
	grayscale : Elem(a), Bool -> Elem(a)
	grayscale = |elem, value| match elem {
		Image(props) => Image({ ..props, grayscale: value })
		Component(bound) => through_boundary(bound, |rendered| grayscale(rendered, value))
		_ => elem
	}

	## A checkbox's unchecked box colour.
	box_bg : Elem(a), Style.Color -> Elem(a)
	box_bg = |elem, value| match elem {
		Checkbox(props) => Checkbox({ ..props, box_bg: value })
		Component(bound) => through_boundary(bound, |rendered| box_bg(rendered, value))
		_ => elem
	}

	## A checkbox's checked box colour.
	box_checked_bg : Elem(a), Style.Color -> Elem(a)
	box_checked_bg = |elem, value| match elem {
		Checkbox(props) => Checkbox({ ..props, box_checked_bg: value })
		Component(bound) => through_boundary(bound, |rendered| box_checked_bg(rendered, value))
		_ => elem
	}

	## A checkbox's box border colour.
	box_border : Elem(a), Style.Color -> Elem(a)
	box_border = |elem, value| match elem {
		Checkbox(props) => Checkbox({ ..props, box_border: value })
		Component(bound) => through_boundary(bound, |rendered| box_border(rendered, value))
		_ => elem
	}

	## A checkbox's check mark colour.
	mark_color : Elem(a), Style.Color -> Elem(a)
	mark_color = |elem, value| match elem {
		Checkbox(props) => Checkbox({ ..props, mark_color: value })
		Component(bound) => through_boundary(bound, |rendered| mark_color(rendered, value))
		_ => elem
	}

	## A panel's visible heading.
	heading : Elem(a), Str -> Elem(a)
	heading = |elem, value| match elem {
		Panel(panel_value) => Panel({ ..panel_value, props: { ..panel_value.props, heading: value } })
		Component(bound) => through_boundary(bound, |rendered| heading(rendered, value))
		_ => elem
	}

	## A panel heading's text size.
	heading_size : Elem(a), U32 -> Elem(a)
	heading_size = |elem, value| match elem {
		Panel(panel_value) => Panel({ ..panel_value, props: { ..panel_value.props, heading_size: value } })
		Component(bound) => through_boundary(bound, |rendered| heading_size(rendered, value))
		_ => elem
	}

	## A panel heading's text weight.
	heading_weight : Elem(a), U32 -> Elem(a)
	heading_weight = |elem, value| match elem {
		Panel(panel_value) => Panel({ ..panel_value, props: { ..panel_value.props, heading_weight: value } })
		Component(bound) => through_boundary(bound, |rendered| heading_weight(rendered, value))
		_ => elem
	}

	## A panel heading's colour.
	heading_color : Elem(a), Style.Color -> Elem(a)
	heading_color = |elem, value| match elem {
		Panel(panel_value) => Panel({ ..panel_value, props: { ..panel_value.props, heading_color: value } })
		Component(bound) => through_boundary(bound, |rendered| heading_color(rendered, value))
		_ => elem
	}

	## Handle a button press.
	on_press : Elem(a), (a, Event.Press => Action(a)) -> Elem(a)
	on_press = |elem, handler!| match elem {
		ActionButton(value) => ActionButton({ ..value, on_press: handler! })
		_ => elem
	}

	## Handle the pointer entering an element. A button and a popover report
	## it themselves; any other element is wrapped in a hover region that
	## reports it and presents nothing.
	on_hover_enter : Elem(a), (a, Event.Hover => Action(a)) -> Elem(a)
	on_hover_enter = |elem, handler!| match elem {
		ActionButton(value) => ActionButton({ ..value, on_hover_enter: Some(handler!) })
		Popover(value) => Popover({ ..value, props: { ..value.props, on_hover_enter: Some(handler!) } })
		_ => hover_region(elem, Some(handler!), None)
	}

	## Handle the pointer leaving an element, wrapping it in a hover region
	## exactly as `on_hover_enter` does.
	on_hover_exit : Elem(a), (a, Event.Hover => Action(a)) -> Elem(a)
	on_hover_exit = |elem, handler!| match elem {
		ActionButton(value) => ActionButton({ ..value, on_hover_exit: Some(handler!) })
		Popover(value) => Popover({ ..value, props: { ..value.props, on_hover_exit: Some(handler!) } })
		_ => hover_region(elem, None, Some(handler!))
	}

	hover_region : Elem(a), [None, Some((a, Event.Hover => Action(a)))], [None, Some((a, Event.Hover => Action(a)))] -> Elem(a)
	hover_region = |anchor, enter, exit| Popover({ children: [anchor], props: { label: "", placement: Below, delay_ms: 0, on_hover_enter: enter, on_hover_exit: exit, style: Style.{} } })

	## Handle a checkbox being toggled.
	on_check : Elem(a), (a, Event.Check => Action(a)) -> Elem(a)
	on_check = |elem, handler!| match elem {
		Checkbox(value) => Checkbox({ ..value, on_change: handler! })
		_ => elem
	}

	## Handle an edit to a text input.
	on_change : Elem(a), (a, Event.TextChange => Action(a)) -> Elem(a)
	on_change = |elem, handler!| match elem {
		TextInput(value) => TextInput({ ..value, on_change: handler! })
		_ => elem
	}

	## Handle a text input being submitted.
	on_submit : Elem(a), (a, Event.TextSubmit => Action(a)) -> Elem(a)
	on_submit = |elem, handler!| match elem {
		TextInput(value) => TextInput({ ..value, on_submit: handler! })
		_ => elem
	}

	## Handle an edit to a textarea.
	on_input : Elem(a), (a, Event.Input => Action(a)) -> Elem(a)
	on_input = |elem, handler!| match elem {
		Textarea(value) => Textarea({ ..value, on_input: handler! })
		_ => elem
	}

	## Handle a dialog being dismissed.
	on_dismiss : Elem(a), (a, Event.Dismiss => Action(a)) -> Elem(a)
	on_dismiss = |elem, handler!| match elem {
		Dialog(value) => Dialog({ ..value, props: { ..value.props, on_dismiss: handler! } })
		_ => elem
	}

	## Handle a pointer gesture on a canvas.
	on_pointer : Elem(a), (a, Event.CanvasPointer => Action(a)) -> Elem(a)
	on_pointer = |elem, handler!| match elem {
		Canvas(value) => Canvas({ ..value, on_pointer: handler! })
		_ => elem
	}

	keyed_col : (item -> Elem(item)), ColProps, KeyedColConfig(parent, item) -> Elem(parent)
	keyed_col = |render_item, props, KeyedColConfig.(config)| Component(
		BoundComponent.{
			key: Some(config.key),
			render: |parent, done!| {
				sequence = (config.get)(parent)
				transition = KeyedSeq.last_transition(sequence)
				item_elem = |key| {
					get_item = |latest| match KeyedSeq.get((config.get)(latest), key) {
						Ok(item) => Ok(item)
						Err(_) => Err(Removed)
					}
					set_item = |latest, item| match KeyedSeq.set_local((config.get)(latest), key, item) {
						Ok(next) => Ok((config.set)(latest, next))
						Err(_) => Err(Removed)
					}
					try_translate(render_item, { key, get: get_item, set: set_item, on_delegate: |candidate| (config.on_delegate)(candidate, key) })
				}
				var $operations = []
				var $children = []
				var $keys = []
				for edit in transition.edits {
					match edit {
						InsertBefore(key, _value, placement) => {
							$operations = $operations.append(KeyedInsert(key, placement))
							$keys = $keys.append(key)
							$children = $children.append(item_elem(key))
						}
						MoveBefore(key, placement) => {
							$operations = $operations.append(KeyedMove(key, placement))
						}
						Remove(key) => {
							$operations = $operations.append(KeyedRemove(key))
						}
						Set(key, _value) => {
							$operations = $operations.append(KeyedSet(key))
							$keys = $keys.append(key)
							$children = $children.append(item_elem(key))
						}
					}
				}
				full = Box.box(
					|{}| {
						entries = KeyedSeq.to_list(sequence)
						Host.component_work!(10, entries.len())
						{ children: entries.map(|entry| item_elem(entry.key)), keys: entries.map(|entry| entry.key) }
					},
				)
				Work.next(|| done!(KeyedColumn({ base_revision: transition.base_revision, children: $children, full, keys: $keys, operations: $operations, props: { label: props.label, style: style_of(props) }, revision: transition.revision })))
			},
			exists: |_parent, done!| Work.next(|| done!(True)),
			remember: None,
			transparent: False,
		},
	)

	## Present one modal surface, focus its first enabled control, trap keyboard
	## traversal inside it, and restore its opener after dismissal.
	dialog : DialogProps(a), List(Elem(a)) -> Elem(a)
	dialog = |props, children| Dialog({ children, props: { label: props.label, on_dismiss: props.on_dismiss, style: style_of(props) } })

	## Annotate `anchor` with a surface presenting `content` beside it. The
	## surface does not block the rest of the window: it opens while the pointer
	## rests on the anchor or keyboard focus is inside it, and Escape closes it.
	popover : PopoverProps(a), Elem(a), List(Elem(a)) -> Elem(a)
	popover = |props, anchor, content| Popover({
		children: [anchor].concat(content),
		props: { label: props.label, placement: props.placement, delay_ms: props.delay_ms, on_hover_enter: props.on_hover_enter, on_hover_exit: props.on_hover_exit, style: style_of(props) },
	})

	## Annotate an element with a short text tooltip, named by that text.
	tooltip : Elem(a), Str -> Elem(a)
	tooltip = |anchor, value| popover({ label: value }, anchor, [Text(value)])

	## Group children in a labelled padded, bordered, rounded vertical surface.
	panel : PanelProps, List(Elem(a)) -> Elem(a)
	panel = |props, children| Panel({
		children,
		props: { label: props.label, heading: props.heading, heading_size: props.heading_size, heading_weight: props.heading_weight, heading_color: props.heading_color, style: style_of(props) },
	})

	## Constrain `content` to the available space and allow scrolling.
	scroll : ScrollProps(a) -> Elem(a)
	scroll = |props| Scroll({ axis: props.axis, content: props.content, label: props.label, style: style_of(props) })

	## Present fixed-height rows while materializing only the visible native range.
	virtual_list : VirtualListProps(a) -> Elem(a)
	virtual_list = |props| if props.row_height == 0 or props.row_height > 16384 {
		crash "Gui virtual row height must be between 1 and 16384"
	} else {
		VirtualList({ items: props.items, label: props.label, row_height: props.row_height, row_gap: props.row_gap, style: style_of(props), provider: None })
	}

	## Present `count` fixed-height rows, building each with `render_row` only
	## while it is near the viewport. The list is its own render boundary: when
	## scrolling brings unbuilt rows near, the platform renders the list alone,
	## from the renderer's most recent `render_row`, without rendering its owner.
	## The boundary is transparent, so an action raised by a row or by
	## `on_range` belongs to the list's owner, exactly as if the rows had been
	## built there.
	virtual_rows : VirtualRowsProps(a) -> Elem(a)
	virtual_rows = |props| if props.row_height == 0 or props.row_height > 16384 {
		crash "Gui virtual row height must be between 1 and 16384"
	} else {
		provider = { count: props.count, render_row: props.render_row, row_key: props.row_key, scroll_to: props.scroll_to, on_range: props.on_range }
		node : Elem(a)
		node = VirtualList({ items: [], label: props.label, row_height: props.row_height, row_gap: props.row_gap, style: style_of(props), provider: Some(provider) })
		Component(BoundComponent.{ key: Some(Key.from_str("Gui.virtual_rows ${props.label}")), render: |_state, done| done(node), exists: |_state, done| done(True), remember: None, transparent: True })
	}

	## Adapt an already-built child tree to parent state.
	lift : Elem(child), (parent -> child), (parent, child -> parent) -> Elem(parent)
	lift = |elem, get_child, set_child| {
		project = |parent, done| Work.get(|| done(Ok(get_child(parent))))
		set = |parent, child| Ok(set_child(parent, child))
		lift_with(elem, project, set, |action, parent, done| Action.adapt_work!(action, parent, project, set, None, done))
	}

	lift_with : Elem(child), Project(parent, child), (parent, child -> Try(parent, [Removed])), (Action(child), parent, (Action(parent) -> Work) -> Work) -> Elem(parent)
	lift_with = |elem, project, set_child, adapt_action| {
		var $pending = [Visit(elem)]
		var $completed = []
		while !$pending.is_empty() {
			work = $pending.last() ?? crash "missing lift work"
			$pending = $pending.drop_last(1)
			match work {
				Visit(current) => {
					split = lift_split(current)
					shell = lift_shell(split.shell, project, set_child, adapt_action)
					$pending = $pending.append(Finish(shell, split.children.len()))
					for child in lift_reverse(split.children) {
						$pending = $pending.append(Visit(child))
					}
				}
				Finish(shell, count) => {
					var $children = []
					for _ in List.repeat({}, count) {
						child = $completed.last() ?? crash "missing lifted child"
						$completed = $completed.drop_last(1)
						$children = $children.append(child)
					}
					$completed = $completed.append(lift_attach(shell, lift_reverse($children)))
				}
			}
		}
		$completed.last() ?? crash "missing lifted result"
	}

	lift_reverse : List(a) -> List(a)
	lift_reverse = |values| {
		var $result = []
		var $remaining = values.len()
		while $remaining > 0 {
			$remaining = $remaining - 1
			$result = $result.append(values.get($remaining) ?? crash "invalid lift list")
		}
		$result
	}

	# A suspended parent holds only its shallow shell, never the original
	# recursive descriptor. Its children are owned by explicit work items.
	lift_split : Elem(a) -> { shell : Elem(a), children : List(Elem(a)) }
	lift_split = |elem| match elem {
		Row(value) => { shell: Row({ ..value, children: [] }), children: value.children }
		Column(value) => { shell: Column({ ..value, children: [] }), children: value.children }
		Dialog(value) => { shell: Dialog({ ..value, children: [] }), children: value.children }
		Popover(value) => { shell: Popover({ ..value, children: [] }), children: value.children }
		Panel(value) => { shell: Panel({ ..value, children: [] }), children: value.children }
		Scroll(value) => { shell: Scroll({ ..value, content: Text("") }), children: [value.content] }
		VirtualList(value) => {
			shell: VirtualList({ ..value, items: value.items.map(|item| { key: item.key, content: Text("") }) }),
			children: value.items.map(|item| item.content),
		}
		_ => { shell: elem, children: [] }
	}

	lift_attach : Elem(a), List(Elem(a)) -> Elem(a)
	lift_attach = |shell, children| match shell {
		Row(value) => Row({ ..value, children })
		Column(value) => Column({ ..value, children })
		Dialog(value) => Dialog({ ..value, children })
		Popover(value) => Popover({ ..value, children })
		Panel(value) => Panel({ ..value, children })
		Scroll(value) => Scroll({ ..value, content: children.first() ?? crash "missing lifted scroll content" })
		VirtualList(value) => {
			var $items = []
			var $index = 0.U64
			for item in value.items {
				$items = $items.append({ key: item.key, content: children.get($index) ?? crash "missing lifted virtual item" })
				$index = $index + 1
			}
			VirtualList({ ..value, items: $items })
		}
		_ => shell
	}

	lift_shell : Elem(child), Project(parent, child), (parent, child -> Try(parent, [Removed])), (Action(child), parent, (Action(parent) -> Work) -> Work) -> Elem(parent)
	lift_shell = |elem, project, set_child, adapt_action| match elem {
		Text(value) => Text(value)
		StyledText(text_value) => StyledText(text_value)
		Row(value) => Row({ props: value.props, children: [] })
		Column(value) => Column({ props: value.props, children: [] })
		KeyedColumn(_) => crash "keyed_col cannot be lifted; construct it at its owning state boundary"
		Dialog(value) => {
			child_handler = value.props.on_dismiss
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Dialog({ children: [], props: { label: value.props.label, style: value.props.style, on_dismiss: parent_handler! } })
		}
		Popover(value) => {
			hover_enter = match value.props.on_hover_enter {
				None => None
				Some(handler) => Some(|parent, event| adapt_event(handler, parent, event, project, adapt_action))
			}
			hover_exit = match value.props.on_hover_exit {
				None => None
				Some(handler) => Some(|parent, event| adapt_event(handler, parent, event, project, adapt_action))
			}
			Popover({ children: [], props: { label: value.props.label, placement: value.props.placement, delay_ms: value.props.delay_ms, on_hover_enter: hover_enter, on_hover_exit: hover_exit, style: value.props.style } })
		}
		Panel(value) => Panel({ props: value.props, children: [] })
		Scroll(scroll_value) => Scroll({ axis: scroll_value.axis, content: Text(""), label: scroll_value.label, style: scroll_value.style })
		VirtualList(list_value) => VirtualList({
			label: list_value.label,
			row_height: list_value.row_height,
			items: list_value.items.map(|item| { key: item.key, content: Text("") }),
			row_gap: list_value.row_gap,
			style: list_value.style,
			provider: match list_value.provider {
				None => None
				Some(provider) => Some(lift_provider(provider, project, set_child, adapt_action))
			},
		})
		TextInput(input_value) => {
			child_change = input_value.on_change
			child_submit = input_value.on_submit
			parent_change! = |parent, event| adapt_event(child_change, parent, event, project, adapt_action)
			parent_submit! = |parent, event| adapt_event(child_submit, parent, event, project, adapt_action)
			TextInput({ label: input_value.label, value: input_value.value, placeholder: input_value.placeholder, enabled: input_value.enabled, on_change: parent_change!, on_submit: parent_submit!, style: input_value.style })
		}
		ActionButton(button_value) => {
			child_handler = button_value.on_press
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			hover_enter = match button_value.on_hover_enter {
				None => None
				Some(handler) => Some(|parent, event| adapt_event(handler, parent, event, project, adapt_action))
			}
			hover_exit = match button_value.on_hover_exit {
				None => None
				Some(handler) => Some(|parent, event| adapt_event(handler, parent, event, project, adapt_action))
			}
			ActionButton({ caption: button_value.caption, label: button_value.label, enabled: button_value.enabled, on_press: parent_handler!, on_hover_enter: hover_enter, on_hover_exit: hover_exit, style: button_value.style })
		}
		Checkbox(checkbox_value) => {
			child_handler = checkbox_value.on_change
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Checkbox({
				label: checkbox_value.label,
				checked: checkbox_value.checked,
				enabled: checkbox_value.enabled,
				box_bg: checkbox_value.box_bg,
				box_checked_bg: checkbox_value.box_checked_bg,
				box_border: checkbox_value.box_border,
				mark_color: checkbox_value.mark_color,
				on_change: parent_handler!,
				style: checkbox_value.style,
			})
		}
		Textarea(textarea_value) => {
			child_handler = textarea_value.on_input
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Textarea({ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, on_input: parent_handler!, style: textarea_value.style })
		}
		Image(image_value) => Image(image_value)
		Canvas(canvas_value) => {
			child_handler = canvas_value.on_pointer
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Canvas({ label: canvas_value.label, primitives: canvas_value.primitives, on_pointer: parent_handler!, style: canvas_value.style })
		}
		Component(bound) => {
			child_render = bound.render
			child_exists = bound.exists
			remember = match bound.remember {
				None => None
				Some(capture) => Some(
					|parent, captured| Work.next(
						|| project(
							parent,
							|result| match result {
								Err(Removed) => crash "cannot remember a removed boundary"
								Ok(child) => Work.next(
									|| capture(
										child,
										|boxed_test| {
											Work.next(|| captured(Box.box(|next, compared| projected_test(project, boxed_test, next, compared))))
										},
									),
								)
							},
						),
					),
				)
			}
			render_parent = |parent, done| Work.next(
				|| project(
					parent,
					|result| match result {
						Err(Removed) => crash "render emitted a removed component"
						Ok(child) => Work.next(|| child_render(child, |rendered| Work.next(|| done(lift_with(rendered, project, set_child, adapt_action)))))
					},
				),
			)
			exists_parent = |parent, done| Work.next(
				|| project(
					parent,
					|result| match result {
						Err(Removed) => Work.next(|| done(False))
						Ok(child) => Work.next(|| child_exists(child, done))
					},
				),
			)
			Component(BoundComponent.{ key: bound.key, render: render_parent, exists: exists_parent, remember, transparent: bound.transparent })
		}
	}

	# A provided row is lifted when the platform asks for it, so adapting a
	# list costs nothing for the rows it never builds.
	lift_provider : RowProvider(child), Project(parent, child), (parent, child -> Try(parent, [Removed])), (Action(child), parent, (Action(parent) -> Work) -> Work) -> RowProvider(parent)
	lift_provider = |provider, project, set_child, adapt_action| {
		child_render = provider.render_row
		parent_render : U64 -> Elem(parent)
		parent_render = |index| lift_with(child_render(index), project, set_child, adapt_action)
		on_range = match provider.on_range {
			None => None
			Some(handler) => Some(|parent, event| adapt_event(handler, parent, event, project, adapt_action))
		}
		{ count: provider.count, render_row: parent_render, row_key: provider.row_key, scroll_to: provider.scroll_to, on_range }
	}

	snapshot_test : Project(parent, child), (child, child -> Bool), child, parent, (Bool -> Work) -> Work
	snapshot_test = |project, compare, previous, next, compared| Work.next(
		|| project(
			next,
			|result| Work.next(
				|| compared(
					match result {
						Err(Removed) => False
						Ok(value) => compare(previous, value)
					},
				),
			),
		),
	)

	projected_test : Project(parent, child), Box((child, (Bool -> Work) -> Work)), parent, (Bool -> Work) -> Work
	projected_test = |project, boxed_test, next, compared| Work.next(
		|| project(
			next,
			|result| match result {
				Err(Removed) => Work.next(|| compared(False))
				Ok(value) => Work.next(|| (Box.unbox(boxed_test))(value, compared))
			},
		),
	)

	adapt_event : (child, event => Action(child)), parent, event, Project(parent, child), (Action(child), parent, (Action(parent) -> Work) -> Work) -> Action(parent)
	adapt_event = |handler!, parent, event, project, adapt| Action.deferred(
		|done| Work.next(
			|| project(
				parent,
				|result| match result {
					Err(Removed) => Work.next(|| done(Action.none))
					Ok(child) => Work.next(|| adapt(handler!(child, event), parent, done))
				},
			),
		),
	)

	## Reveal an element descriptor. This supports platform-side traversal and
	## libraries that transform element trees.
	inspect : Elem(a) -> [
		Component(BoundComponent(a)),
		ActionButton(ButtonNode(a)),
		Checkbox(CheckboxNode(a)),
		Textarea(TextareaNode(a)),
		Image(ImageNode),
		Canvas(CanvasNode(a)),
		Column({ children : List(Elem(a)), props : Frame }),
		KeyedColumn({ base_revision : U64, children : List(Elem(a)), full : Box({} => { children : List(Elem(a)), keys : List(Key) }), keys : List(Key), operations : List(KeyedOperation), props : Frame, revision : U64 }),
		Dialog({ children : List(Elem(a)), props : DialogNode(a) }),
		Popover({ children : List(Elem(a)), props : PopoverNode(a) }),
		Panel({ children : List(Elem(a)), props : PanelNode }),
		Row({ children : List(Elem(a)), props : Frame }),
		Scroll(ScrollNode(a)),
		VirtualList(VirtualListNode(a)),
		TextInput(TextInputNode(a)),
		StyledText(TextNode),
		Text(Str),
	]
	inspect = |value| match value {
		Component(bound) => Component(bound)
		ActionButton(button_value) => ActionButton(button_value)
		Checkbox(checkbox_value) => Checkbox(checkbox_value)
		Textarea(textarea_value) => Textarea(textarea_value)
		Image(image_value) => Image(image_value)
		Canvas(canvas_value) => Canvas(canvas_value)
		Column(children) => Column(children)
		KeyedColumn(keyed_value) => KeyedColumn(keyed_value)
		Dialog(dialog_value) => Dialog(dialog_value)
		Popover(popover_value) => Popover(popover_value)
		Panel(children) => Panel(children)
		Row(children) => Row(children)
		Scroll(scroll_value) => Scroll(scroll_value)
		VirtualList(list_value) => VirtualList(list_value)
		TextInput(input_value) => TextInput(input_value)
		StyledText(styled_value) => StyledText(styled_value)
		Text(text_value) => Text(text_value)
	}
}

expect {
	# Literal conversion through an imported nominal type and a config field.
	boundary = Elem.translate_with(|value| Elem.text(value), { key: "左 boundary with a deliberately long application identity", get: |parent| parent.value, set: |parent, value| { ..parent, value } })
	match Elem.inspect(boundary) {
		Component(bound) => match bound.key {
			Some(key) => key == Key.from_str("左 boundary with a deliberately long application identity")
			None => False
		}
		_ => False
	}
}

expect {
	# Ordinary translations neither require equality nor capture a memo input.
	boundary = Elem.translate(|callback| Elem.text(callback()), |parent| parent.callback, |parent, callback| { ..parent, callback })
	match Elem.inspect(boundary) {
		Component(bound) => match (bound.key, bound.remember) {
			(None, None) => True
			_ => False
		}
		_ => False
	}
}

# Fallible projection execution is effectful and is exercised by the
# review-queue missing-projection and delayed-completion specifications.

expect {
	# Imported Key equality and hashing agree across literal and runtime paths.
	literal : Key
	literal = "左 🦆 a long application key without a short-string limit"
	computed = Key.from_str("左 🦆 a long application key without a short-string limit")
	keys = Dict.single(literal, 42.I64)
	literal == computed and Dict.get(keys, computed) == Ok(42) and Dict.get(keys, Key.id(42)) == Err(KeyNotFound)
}

expect {
	# A hover handler on an element that is not a button wraps it in one hover
	# region, and a second handler joins that region rather than nesting.
	entered : Elem(U64)
	entered = Elem.text("cell").on_hover_enter(|state, _| Action.update(state + 1))
	both = entered.on_hover_exit(|state, _| Action.update(state - 1))
	match Elem.inspect(both) {
		Popover(value) => match (value.props.on_hover_enter, value.props.on_hover_exit, value.children.len()) {
			(Some(_), Some(_), 1) => value.props.label == ""
			_ => False
		}
		_ => False
	}
}

expect {
	# A modifier on a popover reaches its anchor; the surface keeps its props.
	noted : Elem(U64)
	noted = Elem.tooltip(Elem.text("cell"), "About the cell").label("Cell")
	match Elem.inspect(noted) {
		Popover(value) => value.props.label == "About the cell" and value.children.len() == 2
		_ => False
	}
}
