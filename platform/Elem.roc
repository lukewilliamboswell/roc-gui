import Action
import Event
import Gui
import Host
import Key
import KeyedSeq
import Work

## A declarative UI tree whose event handlers transition application state `a`.
## Use `text`, `action_button`, `checkbox`, `row`, `col`, and `panel` to build a tree, and
## `translate` or `lift` to embed UI over smaller component state.
Elem(a) :: [
	Component(BoundComponent(a)),
	ActionButton(ActionButtonProps(a)),
	Checkbox(CheckboxProps(a)),
	Textarea(TextareaProps(a)),
	Image(ImageProps),
	Canvas(CanvasProps(a)),
	Column({ children : List(Elem(a)), props : ColProps }),
	KeyedColumn({ base_revision : U64, children : List(Elem(a)), full : Box({} => { children : List(Elem(a)), keys : List(Key) }), keys : List(Key), operations : List(KeyedOperation), props : ColProps, revision : U64 }),
	Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
	Panel({ children : List(Elem(a)), props : PanelProps }),
	Row({ children : List(Elem(a)), props : RowProps }),
	Scroll(ScrollProps(a)),
	VirtualList(VirtualListProps(a)),
	TextInput(TextInputProps(a)),
	StyledText(TextProps),
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
		render_boundary = |parent, done| Work.next(
			|| project(
				parent,
				|result| match result {
					Err(Removed) => crash "render emitted a removed component"
					Ok(child) => Work.next(|| done(lift_with(render(child), project, set, adapt)))
				},
			),
		)
		exists = |parent, done| Work.next(
			|| project(
				parent,
				|result| Work.next(
					|| done(
						match result {
							Ok(_) => True
							Err(Removed) => False
						},
					),
				),
			),
		)
		Component(BoundComponent.{ key, render: render_boundary, exists: exists, remember })
	}

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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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

		## The panel's own visible heading, distinct from `label`, which stays a
		## semantic locator. An empty heading paints none. `heading_size`,
		## `heading_weight`, and `heading_color` set it apart from the panel's
		## body text; each zero or `Default` keeps the panel's own.
		heading : Str ?? "",
		heading_size : U32 ?? 0,
		heading_weight : U32 ?? 0,
		heading_color : Gui.Color ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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

		## Optional pointer transitions; absent handlers allocate no event routes.
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))] ?? None,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Clip,
		overflow_y : Gui.Overflow ?? Clip,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for a vertically scrollable region. `name` is its stable
	## semantic identity for specifications and accessibility.
	ScrollAxis : [Both, Horizontal, Vertical]
	ScrollProps(a) := {
		axis : ScrollAxis ?? Vertical,
		content : Elem(a),
		label : Str,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## One stable row in a virtual list. `key` identifies the row independently
	## of its current index, while `content` is an ordinary element tree.
	VirtualListItem(a) := { content : Elem(a), key : U64 }

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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
		text_overflow : Gui.TextOverflow ?? Wrap,
		overflow_x : Gui.Overflow ?? Visible,
		overflow_y : Gui.Overflow ?? Visible,
		align : Gui.Align ?? Default,
		justify : Gui.Justify ?? Default,
	}

	## Properties for `checkbox`. `label` is both visible text and the stable
	## semantic name used by specifications. `on_change` receives the requested
	## checked state. The common visual fields mirror `Gui.Style`; defaults let a
	## record literal name only the properties it changes.
	CheckboxProps(a) := {
		label : Str,
		checked : Bool,
		enabled : Bool ?? True,
		on_change : (a, Event.Check => Action(a)),

		## The indicator's own colours. `fg` reaches the caption; these reach the
		## box and its mark, which otherwise keep host values chosen for a dark
		## ground. Each defaults to the host's own.
		box_bg : Gui.Color ?? Default,
		box_checked_bg : Gui.Color ?? Default,
		box_border : Gui.Color ?? Default,
		mark_color : Gui.Color ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Gui.Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : Gui.FontFace ?? Default,
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

	## Properties for `styled_text`. A string is the only thing a typographic
	## step is about, so these are the type fields alone: a typographic step
	## costs no container, and none of a container's layout is implied.
	TextProps := {
		value : Str,
		fg : Gui.Color ?? Default,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		font_face : Gui.FontFace ?? Default,
	}

	## Display literal text. It inherits colour and size from its container.
	text : Str -> Elem(a)
	text = |value| Text(value)

	## Display text in its own colour, size, weight, and face, without a
	## container element that exists only to carry them.
	styled_text : TextProps -> Elem(a)
	styled_text = |props| StyledText(props)

	## Display a named text button and handle presses. `caption` is its visible
	## text and `label` is its stable semantic locator, the same two names the
	## styled `action_button` and every other control use.
	ButtonProps(a) := {
		caption : Str,
		label : Str,
		on_press : a, Event.Press => Action(a),
		on_hover_enter : [None, Some((a, Event.Hover => Action(a)))] ?? None,
		on_hover_exit : [None, Some((a, Event.Hover => Action(a)))] ?? None,
	}

	button : ButtonProps(a) -> Elem(a)
	button = |props| ActionButton(ActionButtonProps.{ caption: props.caption, label: props.label, on_press: props.on_press, on_hover_enter: props.on_hover_enter, on_hover_exit: props.on_hover_exit })

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

	keyed_col : (item -> Elem(item)), ColProps, KeyedColConfig(parent, item) -> Elem(parent)
	keyed_col = |render_item, props, KeyedColConfig.(config)| Component(BoundComponent.{
		key: Some(config.key),
		render: |parent, done!| {
			sequence = (config.get)(parent)
			transition = KeyedSeq.last_transition(sequence)
			item_elem = |key| {
				get_item = |latest| match KeyedSeq.get((config.get)(latest), key) { Ok(item) => Ok(item) Err(_) => Err(Removed) }
				set_item = |latest, item| match KeyedSeq.set_local((config.get)(latest), key, item) { Ok(next) => Ok((config.set)(latest, next)) Err(_) => Err(Removed) }
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
					MoveBefore(key, placement) => { $operations = $operations.append(KeyedMove(key, placement)) }
					Remove(key) => { $operations = $operations.append(KeyedRemove(key)) }
					Set(key, _value) => {
						$operations = $operations.append(KeyedSet(key))
						$keys = $keys.append(key)
						$children = $children.append(item_elem(key))
					}
				}
			}
			full = Box.box(|{}| {
				entries = KeyedSeq.to_list(sequence)
				Host.component_work!(10, entries.len())
				{ children: entries.map(|entry| item_elem(entry.key)), keys: entries.map(|entry| entry.key) }
			})
			Work.next(|| done!(KeyedColumn({ base_revision: transition.base_revision, children: $children, full, keys: $keys, operations: $operations, props, revision: transition.revision })))
		},
		exists: |_parent, done!| Work.next(|| done!(True)),
		remember: None,
	})

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
			Dialog({
				children: [],
				props: DialogProps.{ label: value.props.label, on_dismiss: parent_handler!, gap: value.props.gap, padding: value.props.padding, padding_top: value.props.padding_top, padding_right: value.props.padding_right, padding_bottom: value.props.padding_bottom, padding_left: value.props.padding_left, width: value.props.width, height: value.props.height, min_width: value.props.min_width, min_height: value.props.min_height, max_width: value.props.max_width, max_height: value.props.max_height, grow: value.props.grow, bg: value.props.bg, hover_bg: value.props.hover_bg, active_bg: value.props.active_bg, disabled_bg: value.props.disabled_bg, disabled_fg: value.props.disabled_fg, focus_color: value.props.focus_color, fg: value.props.fg, border_color: value.props.border_color, border_width: value.props.border_width, border_top: value.props.border_top, border_right: value.props.border_right, border_bottom: value.props.border_bottom, border_left: value.props.border_left, radius: value.props.radius, font_size: value.props.font_size, font_weight: value.props.font_weight, shadow: value.props.shadow, shadow_y: value.props.shadow_y, shadow_color: value.props.shadow_color, shadow_alpha: value.props.shadow_alpha, font_face: value.props.font_face, text_overflow: value.props.text_overflow, overflow_x: value.props.overflow_x, overflow_y: value.props.overflow_y, align: value.props.align, justify: value.props.justify },
			})
		}
		Panel(value) => Panel({ props: value.props, children: [] })
		Scroll(scroll_value) => Scroll(
			ScrollProps.{
				axis: scroll_value.axis,
				content: Text(""),
				label: scroll_value.label,
				gap: scroll_value.gap,
				padding: scroll_value.padding,
				padding_top: scroll_value.padding_top,
				padding_right: scroll_value.padding_right,
				padding_bottom: scroll_value.padding_bottom,
				padding_left: scroll_value.padding_left,
				width: scroll_value.width,
				height: scroll_value.height,
				min_width: scroll_value.min_width,
				min_height: scroll_value.min_height,
				max_width: scroll_value.max_width,
				max_height: scroll_value.max_height,
				grow: scroll_value.grow,
				bg: scroll_value.bg,
				hover_bg: scroll_value.hover_bg,
				active_bg: scroll_value.active_bg,
				disabled_bg: scroll_value.disabled_bg,
				disabled_fg: scroll_value.disabled_fg,
				focus_color: scroll_value.focus_color,
				fg: scroll_value.fg,
				border_color: scroll_value.border_color,
				border_width: scroll_value.border_width,
				border_top: scroll_value.border_top,
				border_right: scroll_value.border_right,
				border_bottom: scroll_value.border_bottom,
				border_left: scroll_value.border_left,
				radius: scroll_value.radius,
				font_size: scroll_value.font_size,
				font_weight: scroll_value.font_weight,
				shadow: scroll_value.shadow,
				shadow_y: scroll_value.shadow_y,
				shadow_color: scroll_value.shadow_color,
				shadow_alpha: scroll_value.shadow_alpha,
				font_face: scroll_value.font_face,
				text_overflow: scroll_value.text_overflow,
				overflow_x: scroll_value.overflow_x,
				overflow_y: scroll_value.overflow_y,
				align: scroll_value.align,
				justify: scroll_value.justify,
			},
		)
		VirtualList(list_value) => VirtualList(
			VirtualListProps.{
				label: list_value.label,
				row_height: list_value.row_height,
				items: list_value.items.map(|item| { key: item.key, content: Text("") }),
				row_gap: list_value.row_gap,
				gap: list_value.gap,
				padding: list_value.padding,
				padding_top: list_value.padding_top,
				padding_right: list_value.padding_right,
				padding_bottom: list_value.padding_bottom,
				padding_left: list_value.padding_left,
				width: list_value.width,
				height: list_value.height,
				min_width: list_value.min_width,
				min_height: list_value.min_height,
				max_width: list_value.max_width,
				max_height: list_value.max_height,
				grow: list_value.grow,
				bg: list_value.bg,
				hover_bg: list_value.hover_bg,
				active_bg: list_value.active_bg,
				disabled_bg: list_value.disabled_bg,
				disabled_fg: list_value.disabled_fg,
				focus_color: list_value.focus_color,
				fg: list_value.fg,
				border_color: list_value.border_color,
				border_width: list_value.border_width,
				border_top: list_value.border_top,
				border_right: list_value.border_right,
				border_bottom: list_value.border_bottom,
				border_left: list_value.border_left,
				radius: list_value.radius,
				font_size: list_value.font_size,
				font_weight: list_value.font_weight,
				shadow: list_value.shadow,
				shadow_y: list_value.shadow_y,
				shadow_color: list_value.shadow_color,
				shadow_alpha: list_value.shadow_alpha,
				font_face: list_value.font_face,
				text_overflow: list_value.text_overflow,
				overflow_x: list_value.overflow_x,
				overflow_y: list_value.overflow_y,
				align: list_value.align,
				justify: list_value.justify,
			},
		)
		TextInput(input_value) => {
			child_change = input_value.on_change
			child_submit = input_value.on_submit
			parent_change! = |parent, event| adapt_event(child_change, parent, event, project, adapt_action)
			parent_submit! = |parent, event| adapt_event(child_submit, parent, event, project, adapt_action)
			TextInput(TextInputProps.{ label: input_value.label, value: input_value.value, placeholder: input_value.placeholder, enabled: input_value.enabled, on_change: parent_change!, on_submit: parent_submit!, gap: input_value.gap, padding: input_value.padding, padding_top: input_value.padding_top, padding_right: input_value.padding_right, padding_bottom: input_value.padding_bottom, padding_left: input_value.padding_left, width: input_value.width, height: input_value.height, min_width: input_value.min_width, min_height: input_value.min_height, max_width: input_value.max_width, max_height: input_value.max_height, grow: input_value.grow, bg: input_value.bg, hover_bg: input_value.hover_bg, active_bg: input_value.active_bg, disabled_bg: input_value.disabled_bg, disabled_fg: input_value.disabled_fg, focus_color: input_value.focus_color, fg: input_value.fg, border_color: input_value.border_color, border_width: input_value.border_width, border_top: input_value.border_top, border_right: input_value.border_right, border_bottom: input_value.border_bottom, border_left: input_value.border_left, radius: input_value.radius, font_size: input_value.font_size, font_weight: input_value.font_weight, shadow: input_value.shadow, shadow_y: input_value.shadow_y, shadow_color: input_value.shadow_color, shadow_alpha: input_value.shadow_alpha, font_face: input_value.font_face, text_overflow: input_value.text_overflow, overflow_x: input_value.overflow_x, overflow_y: input_value.overflow_y, align: input_value.align, justify: input_value.justify })
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
			ActionButton(
				ActionButtonProps.{
					caption: button_value.caption,
					label: button_value.label,
					enabled: button_value.enabled,
					on_press: parent_handler!,
					on_hover_enter: hover_enter,
					on_hover_exit: hover_exit,
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
					shadow: button_value.shadow,
					shadow_y: button_value.shadow_y,
					shadow_color: button_value.shadow_color,
					shadow_alpha: button_value.shadow_alpha,
					font_face: button_value.font_face,
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
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Checkbox(
				CheckboxProps.{
					label: checkbox_value.label,
					checked: checkbox_value.checked,
					enabled: checkbox_value.enabled,
					box_bg: checkbox_value.box_bg,
					box_checked_bg: checkbox_value.box_checked_bg,
					box_border: checkbox_value.box_border,
					mark_color: checkbox_value.mark_color,
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
					shadow: checkbox_value.shadow,
					shadow_y: checkbox_value.shadow_y,
					shadow_color: checkbox_value.shadow_color,
					shadow_alpha: checkbox_value.shadow_alpha,
					font_face: checkbox_value.font_face,
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
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Textarea(TextareaProps.{ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, on_input: parent_handler!, gap: textarea_value.gap, padding: textarea_value.padding, padding_top: textarea_value.padding_top, padding_right: textarea_value.padding_right, padding_bottom: textarea_value.padding_bottom, padding_left: textarea_value.padding_left, width: textarea_value.width, height: textarea_value.height, min_width: textarea_value.min_width, min_height: textarea_value.min_height, max_width: textarea_value.max_width, max_height: textarea_value.max_height, grow: textarea_value.grow, bg: textarea_value.bg, hover_bg: textarea_value.hover_bg, active_bg: textarea_value.active_bg, disabled_bg: textarea_value.disabled_bg, disabled_fg: textarea_value.disabled_fg, focus_color: textarea_value.focus_color, fg: textarea_value.fg, border_color: textarea_value.border_color, border_width: textarea_value.border_width, border_top: textarea_value.border_top, border_right: textarea_value.border_right, border_bottom: textarea_value.border_bottom, border_left: textarea_value.border_left, radius: textarea_value.radius, font_size: textarea_value.font_size, font_weight: textarea_value.font_weight, shadow: textarea_value.shadow, shadow_y: textarea_value.shadow_y, shadow_color: textarea_value.shadow_color, shadow_alpha: textarea_value.shadow_alpha, font_face: textarea_value.font_face, text_overflow: textarea_value.text_overflow, overflow_x: textarea_value.overflow_x, overflow_y: textarea_value.overflow_y, align: textarea_value.align, justify: textarea_value.justify })
		}
		Image(image_value) => Image(image_value)
		Canvas(canvas_value) => {
			child_handler = canvas_value.on_pointer
			parent_handler! = |parent, event| adapt_event(child_handler, parent, event, project, adapt_action)
			Canvas(CanvasProps.{ label: canvas_value.label, primitives: canvas_value.primitives, on_pointer: parent_handler!, width: canvas_value.width, height: canvas_value.height, min_width: canvas_value.min_width, min_height: canvas_value.min_height, max_width: canvas_value.max_width, max_height: canvas_value.max_height, grow: canvas_value.grow, bg: canvas_value.bg, border_color: canvas_value.border_color, border_width: canvas_value.border_width, border_top: canvas_value.border_top, border_right: canvas_value.border_right, border_bottom: canvas_value.border_bottom, border_left: canvas_value.border_left, radius: canvas_value.radius })
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
			Component(BoundComponent.{ key: bound.key, render: render_parent, exists: exists_parent, remember })
		}
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
		ActionButton(ActionButtonProps(a)),
		Checkbox(CheckboxProps(a)),
		Textarea(TextareaProps(a)),
		Image(ImageProps),
		Canvas(CanvasProps(a)),
		Column({ children : List(Elem(a)), props : ColProps }),
		KeyedColumn({ base_revision : U64, children : List(Elem(a)), full : Box({} => { children : List(Elem(a)), keys : List(Key) }), keys : List(Key), operations : List(KeyedOperation), props : ColProps, revision : U64 }),
		Dialog({ children : List(Elem(a)), props : DialogProps(a) }),
		Panel({ children : List(Elem(a)), props : PanelProps }),
		Row({ children : List(Elem(a)), props : RowProps }),
		Scroll(ScrollProps(a)),
		VirtualList(VirtualListProps(a)),
		TextInput(TextInputProps(a)),
		StyledText(TextProps),
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
