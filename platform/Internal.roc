import Host
import Action
import Elem
import Key
import KeyedSeq
import Style
import Session
import Index
import RouteIds
import Work
import WorkStack

Internal := [].{
	Route(a) : { boundary : U64, id : U64, revision : U64, fire : (a, Str => Action(a)) }

	BoundaryInfo(a) : {
		key : U64,
		parent : [None, Some(U64)],
		path : List(U64),
		render : a, (Elem(a) -> Work) -> Work,
		root : U64,
		bound : [None, Some(Elem.BoundComponent(a))],
		memo : [Unknown, Known(Box((a, (Bool -> Work) -> Work)))],
		revision : U64,
		route_ids : RouteIds,
		children : List(U64),
		keyed_container : U64,
		keyed_revision : U64,
		keyed_items : KeyedSeq(U64),
		keyed : [None, Some(Elem.Frame)],
	}

	Lowered(a) : {
		boundaries : Index(BoundaryInfo(a)),
		root : U64,
		routes : Index(Route(a)),
	}

	BuildingOwner(a) : { key : U64, revision : U64, path : List(U64), route_ids : RouteIds, children : List(U64), keyed_container : U64, keyed_revision : U64, keyed_keys : List(Key), keyed : [None, Some(Elem.Frame)] }

	# Keep active owner metadata compact in the explicit lowering work stack.
	BuildingOwners(a) : { stored : Index(BoundaryInfo(a)), active : Box(BuildingOwner(a)) }

	Building(a) : { boundaries : BuildingOwners(a), root : U64, routes : Index(Route(a)) }

	## Host transaction primitives for keyed columns. Keyed items are complete
	## component boundaries; public Elem construction is added separately.
	keyed_edit_begin! : U64, U64, U64 => {}
	keyed_edit_begin! = |container, base_revision, new_revision| Host.keyed_edit_begin!({ container, base_revision, new_revision })

	keyed_seed! : U64, U64, List(Key) => {}
	keyed_seed! = |container, revision, keys| Host.keyed_seed!({ container, revision, keys: keys.map(Key.to_bytes) })

	keyed_insert_before! : Key, [End, Before(Key)], U64 => {}
	keyed_insert_before! = |key, position, root| {
		before = match position {
			End => []
			Before(anchor) => Key.to_bytes(anchor)
		}
		Host.keyed_insert_before!({ key: Key.to_bytes(key), before, root })
	}

	keyed_remove! : Key => {}
	keyed_remove! = |key| Host.keyed_remove!(Key.to_bytes(key))

	keyed_move_before! : Key, [End, Before(Key)] => {}
	keyed_move_before! = |key, position| Host.keyed_move_before!({
		key: Key.to_bytes(key),
		before: match position {
			End => []
			Before(anchor) => Key.to_bytes(anchor)
		},
	})

	keyed_set! : Key, U64 => {}
	keyed_set! = |key, root| {
		Host.keyed_set!({ key: Key.to_bytes(key), root })
	}

	keyed_edit_commit! : () => {}
	keyed_edit_commit! = || Host.keyed_edit_commit!()

	max_style_value = 16384

	color = |value| match value {
		Default => 0x01000000
		Rgb(rgb) => if rgb <= 0x00ffffff {
			rgb
		} else {
			crash "Gui RGB colors are at most 0xffffff"
		}
	}

	length = |value| match value {
		Auto => { kind: 0, value: 0 }
		Fill => { kind: 1, value: 0 }
		Px(pixels) => if pixels <= max_style_value {
			{ kind: 2, value: pixels }
		} else {
			crash "Gui pixel dimensions are at most 16384 logical pixels"
		}
	}

	overflow = |value| match value {
		Visible => 0
		Clip => 1
		Scroll => 2
	}

	inset = |value, fallback| match value {
		Same => fallback
		Px(pixels) => if pixels <= max_style_value {
			pixels
		} else {
			crash "Gui per-side padding is at most 16384 logical pixels"
		}
	}

	font_face = |value| match value {
		Default => 0
		Monospace => 1
	}

	text_overflow = |value| match value {
		Wrap => 0
		NoWrap => 1
		Ellipsis => 2
	}

	align = |value| match value {
		Default => 0
		Start => 1
		Center => 2
		End => 3
		Baseline => 4
		Stretch => 5
	}

	justify = |value| match value {
		Default => 0
		Start => 1
		Center => 2
		End => 3
		Between => 4
		Around => 5
	}

	style_args = |style| {
		if style.gap > max_style_value or style.padding > max_style_value or style.border_width > max_style_value or style.radius > max_style_value or style.font_size > max_style_value {
			crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
		}
		if style.font_weight != 0 and (style.font_weight < 100 or style.font_weight > 900) {
			crash "Gui font_weight is 0 for the native default, or 100 through 900"
		}
		if style.shadow > max_style_value or style.shadow_y > max_style_value {
			crash "Gui shadow blur and offset are at most 16384 logical pixels"
		}
		if style.shadow_alpha > 100 {
			crash "Gui shadow_alpha is 0 through 100 percent"
		}
		width = length(style.width)
		height = length(style.height)
		min_width = length(style.min_width)
		min_height = length(style.min_height)
		max_width = length(style.max_width)
		max_height = length(style.max_height)
		{
			gap: style.gap,
			padding_top: inset(style.padding_top, style.padding),
			padding_right: inset(style.padding_right, style.padding),
			padding_bottom: inset(style.padding_bottom, style.padding),
			padding_left: inset(style.padding_left, style.padding),
			width_kind: width.kind,
			width: width.value,
			height_kind: height.kind,
			height: height.value,
			min_width_kind: min_width.kind,
			min_width: min_width.value,
			min_height_kind: min_height.kind,
			min_height: min_height.value,
			max_width_kind: max_width.kind,
			max_width: max_width.value,
			max_height_kind: max_height.kind,
			max_height: max_height.value,
			grow: style.grow,
			bg: color(style.bg),
			hover_bg: color(style.hover_bg),
			active_bg: color(style.active_bg),
			disabled_bg: color(style.disabled_bg),
			disabled_fg: color(style.disabled_fg),
			focus_color: color(style.focus_color),
			fg: color(style.fg),
			border_color: color(style.border_color),
			border_top: inset(style.border_top, style.border_width),
			border_right: inset(style.border_right, style.border_width),
			border_bottom: inset(style.border_bottom, style.border_width),
			border_left: inset(style.border_left, style.border_width),
			radius: style.radius,
			font_size: style.font_size,
			font_weight: style.font_weight,
			shadow: style.shadow,
			shadow_y: style.shadow_y,
			shadow_color: color(style.shadow_color),
			shadow_alpha: style.shadow_alpha,
			font_face: font_face(style.font_face),
			text_overflow: text_overflow(style.text_overflow),
			overflow_x: overflow(style.overflow_x),
			overflow_y: overflow(style.overflow_y),
			align: align(style.align),
			justify: justify(style.justify),
		}
	}

	# Native container emission is shared by the explicit completion work items.
	finish_row! = |builder, props| {
		style = style_args(props.style)
		Host.node_row!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_column! = |builder, props| {
		style = style_args(props.style)
		Host.node_column!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_dialog! = |builder, props| {
		style = style_args(props.style)
		Host.node_dialog!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_popover! = |builder, props| {
		if props.delay_ms > 60000 {
			crash "Gui popover delay_ms is at most 60000 milliseconds"
		}
		style = style_args(props.style)
		placement = match props.placement {
			Below => 0
			Above => 1
			Start => 2
			End => 3
		}
		hover_enter = match props.on_hover_enter {
			None => False
			Some(_) => True
		}
		hover_exit = match props.on_hover_exit {
			None => False
			Some(_) => True
		}
		Host.node_popover!({ builder, label: props.label, placement, delay_ms: props.delay_ms, hover_enter, hover_exit, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_panel! = |builder, props| {
		style = style_args(props.style)
		Host.node_panel!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_scroll! = |child, props| {
		axis = match props.axis {
			Vertical => 0
			Horizontal => 1
			Both => 2
		}
		style = style_args(props.style)
		id = Host.node_scroll!({
			axis,
			child: child,
			name: props.label,
			gap: style.gap,
			padding_top: style.padding_top,
			padding_right: style.padding_right,
			padding_bottom: style.padding_bottom,
			padding_left: style.padding_left,
			width_kind: style.width_kind,
			width: style.width,
			height_kind: style.height_kind,
			height: style.height,
			min_width_kind: style.min_width_kind,
			min_width: style.min_width,
			min_height_kind: style.min_height_kind,
			min_height: style.min_height,
			max_width_kind: style.max_width_kind,
			max_width: style.max_width,
			max_height_kind: style.max_height_kind,
			max_height: style.max_height,
			grow: style.grow,
			bg: style.bg,
			hover_bg: style.hover_bg,
			active_bg: style.active_bg,
			disabled_bg: style.disabled_bg,
			disabled_fg: style.disabled_fg,
			focus_color: style.focus_color,
			fg: style.fg,
			border_color: style.border_color,
			border_top: style.border_top,
			border_right: style.border_right,
			border_bottom: style.border_bottom,
			border_left: style.border_left,
			radius: style.radius,
			font_size: style.font_size,
			font_weight: style.font_weight,
			shadow: style.shadow,
			shadow_y: style.shadow_y,
			shadow_color: style.shadow_color,
			shadow_alpha: style.shadow_alpha,
			font_face: style.font_face,
			text_overflow: style.text_overflow,
			overflow_x: style.overflow_x,
			overflow_y: style.overflow_y,
			align: style.align,
			justify: style.justify,
		})
		id
	}

	finish_list! = |builder, props, first, instance| {
		style = style_args(props.style)
		provided = match props.provider {
			None => { count: 0, notify: False }
			Some(provider) => {
				count: provider.count,
				notify: match provider.on_range {
					None => False
					Some(_) => True
				},
			}
		}
		id = Host.node_virtual_list!({
			builder,
			count: provided.count,
			first,
			instance,
			notify: provided.notify,
			name: props.label,
			row_height: props.row_height,
			row_gap: props.row_gap,
			gap: style.gap,
			padding_top: style.padding_top,
			padding_right: style.padding_right,
			padding_bottom: style.padding_bottom,
			padding_left: style.padding_left,
			width_kind: style.width_kind,
			width: style.width,
			height_kind: style.height_kind,
			height: style.height,
			min_width_kind: style.min_width_kind,
			min_width: style.min_width,
			min_height_kind: style.min_height_kind,
			min_height: style.min_height,
			max_width_kind: style.max_width_kind,
			max_width: style.max_width,
			max_height_kind: style.max_height_kind,
			max_height: style.max_height,
			grow: style.grow,
			bg: style.bg,
			hover_bg: style.hover_bg,
			active_bg: style.active_bg,
			disabled_bg: style.disabled_bg,
			disabled_fg: style.disabled_fg,
			focus_color: style.focus_color,
			fg: style.fg,
			border_color: style.border_color,
			border_top: style.border_top,
			border_right: style.border_right,
			border_bottom: style.border_bottom,
			border_left: style.border_left,
			radius: style.radius,
			font_size: style.font_size,
			font_weight: style.font_weight,
			shadow: style.shadow,
			shadow_y: style.shadow_y,
			shadow_color: style.shadow_color,
			shadow_alpha: style.shadow_alpha,
			font_face: style.font_face,
			text_overflow: style.text_overflow,
			overflow_x: style.overflow_x,
			overflow_y: style.overflow_y,
			align: style.align,
			justify: style.justify,
		})
		id
	}

	# Enter/finish work preserves depth-first builder and owner ordering without
	# suspending a Roc call frame per node. Finish items contain shallow props,
	# never a parent descriptor that retains its already-visited descendants.
	## Box the large traversal payloads so LowerWork and every continuation that
	## captures it stay bounded. Leaving these records inline made the pinned
	## development backend generate roughly MiB-sized stack frames and turned
	## full-tree lowering into continuation-copy work proportional to payload size.
	VisitWork(a) : { elem : Elem(a), position : U64 }
	BoundaryWork(a) : { cleared : BoundaryInfo(a), owner : BoundaryInfo(a), parent : Box(BuildingOwner(a)) }

	LowerWork(a) : [
		Visit(Box(VisitWork(a))),
		Append(U64),
		CloseRow(U64, Elem.Frame),
		CloseColumn(U64, Elem.Frame),
		CloseKeyedColumn(U64, Elem.Frame, List(Key), U64),
		CloseDialog(U64, Elem.DialogNode(a)),
		ClosePopover(U64, Elem.PopoverNode(a)),
		ClosePanel(U64, Elem.PanelNode),
		CloseScroll(Elem.ScrollNode(a)),
		CloseList(U64, Elem.VirtualListNode(a), U64),
		OpenItem(U64),
		CloseItem(U64),
		CloseBoundary(Box(BoundaryWork(a))),
	]

	KeyedStep(a) : [KeyedInsert(Key, Box(Elem(a)), KeyedSeq.Placement), KeyedMove(Key, KeyedSeq.Placement), KeyedRemove(Key), KeyedSet(Key, Box(Elem(a)))]

	queue_children : WorkStack(LowerWork(a)), List(Elem(a)), U64 -> WorkStack(LowerWork(a))
	queue_children = |work, children, builder| {
		var $work = work
		var $position = children.len()
		while $position > 0 {
			$position = $position - 1
			child = children.get($position) ?? crash "missing traversal child"
			$work = $work.push(Append(builder)).push(Visit(Box.box({ elem: child, position: $position })))
		}
		$work
	}

	lower! : Elem(a), a, U64, Index(Route(a)), BuildingOwners(a), U64, (Building(a) -> Work) => Work
	lower! = |elem, state, active_boundary, routes, boundaries, position, done!| lower_work!(WorkStack.empty.push(Visit(Box.box({ elem, position }))), state, active_boundary, routes, boundaries, 0, done!)

	lower_work! = |work, state, active_boundary, routes, boundaries, root, done!| {
		var $work = work
		var $routes = routes
		var $boundaries = boundaries
		var $root = root
		var $pending = None
		# Bound one continuation's synchronous work without paying the continuation
		# and generated stack-frame cost once for every individual node.
		var $budget = 4096
		var $active_boundary = active_boundary
		while $budget > 0 and !$work.is_empty() and (match $pending {
			None => True
			Some(_) => False
		}) {
			frame = $work.pop() ?? crash "missing lowering work"
			$budget = $budget - 1
			$work = frame.rest
			match frame.item {
				Visit(boxed_visit) => {
					visit = Box.unbox(boxed_visit)
					current = visit.elem
					child_position = visit.position
					match Elem.inspect(current) {
						Row(value) => {
							Host.scope_enter!(1, value.props.label, child_position)
							builder = Host.children_begin!()
							$work = queue_children($work.push(CloseRow(builder, value.props)), value.children, builder)
						}
						Column(value) => {
							Host.scope_enter!(2, value.props.label, child_position)
							builder = Host.children_begin!()
							$work = queue_children($work.push(CloseColumn(builder, value.props)), value.children, builder)
						}
						KeyedColumn(value) => {
							active = Box.unbox($boundaries.active)
							$boundaries = { stored: $boundaries.stored, active: Box.box({ ..active, keyed: Some(value.props) }) }
							Host.scope_enter!(2, value.props.label, child_position)
							builder = Host.children_begin!()
							full = (Box.unbox(value.full))({})
							$work = queue_children($work.push(CloseKeyedColumn(builder, value.props, full.keys, value.revision)), full.children, builder)
						}
						Dialog(value) => {
							Host.scope_enter!(4, value.props.label, child_position)
							builder = Host.children_begin!()
							$work = queue_children($work.push(CloseDialog(builder, value.props)), value.children, builder)
						}
						Popover(value) => {
							Host.scope_enter!(8, value.props.label, child_position)
							builder = Host.children_begin!()
							$work = queue_children($work.push(ClosePopover(builder, value.props)), value.children, builder)
						}
						Panel(value) => {
							Host.scope_enter!(3, value.props.label, child_position)
							builder = Host.children_begin!()
							if value.props.heading != "" {
								if value.props.heading_size > max_style_value {
									crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
								}
								if value.props.heading_weight != 0 and (value.props.heading_weight < 100 or value.props.heading_weight > 900) {
									crash "Gui font_weight is 0 for the native default, or 100 through 900"
								}
								heading = Host.node_styled_text!({ value: value.props.heading, fg: color(value.props.heading_color), font_size: value.props.heading_size, font_weight: value.props.heading_weight, font_face: 0 })
								Host.children_push!(builder, heading)
							}
							$work = queue_children($work.push(ClosePanel(builder, value.props)), value.children, builder)
						}
						Scroll(value) => {
							Host.scope_enter!(5, value.label, child_position)
							$work = $work.push(CloseScroll({ ..value, content: Elem.text("") })).push(Visit(Box.box({ elem: value.content, position: 0 })))
						}
						VirtualList(value) => {
							Host.scope_enter!(6, value.label, child_position)
							builder = Host.children_begin!()
							match value.provider {
								None => {
									$work = $work.push(CloseList(builder, { ..value, items: [] }, 0))
									var $index = value.items.len()
									while $index > 0 {
										$index = $index - 1
										row = value.items.get($index) ?? crash "missing virtual row"
										$work = $work.push(Append(builder)).push(CloseItem(row.key)).push(Visit(Box.box({ elem: row.content, position: 0 }))).push(OpenItem(row.key))
									}
								}
								Some(provider) => {
									# The host owns the viewport, so it names the rows worth
									# building: those near the viewport, or near a requested row.
									window = rows_window!(provider, value.row_height, $active_boundary)
									$work = $work.push(CloseList(builder, { ..value, items: [] }, window.first))
									var $index = window.end
									while $index > window.first {
										$index = $index - 1
										key = (provider.row_key)($index)
										row = (provider.render_row)($index)
										$work = $work.push(Append(builder)).push(CloseItem(key)).push(Visit(Box.box({ elem: row, position: 0 }))).push(OpenItem(key))
									}
								}
							}
						}
						Component(bound) => {
							remaining = $work
							saved_routes = $routes
							saved_boundaries = $boundaries
							parent_key = $active_boundary
							$pending = Some(
								prepare_component!(
									bound,
									state,
									parent_key,
									saved_routes,
									saved_boundaries,
									|decision| match decision {
										Retained(built) => Work.next(|| lower_work!(remaining, state, parent_key, built.routes, built.boundaries, built.root, done!))
										Descend(owner, parent) => Work.next(
											|| {
												Host.component_enter!(owner.key)
												prepare_rebuild!(owner, state, saved_routes, saved_boundaries.stored, |prepared| Work.next(|| lower_work!(remaining.push(CloseBoundary(Box.box({ owner, cleared: prepared.cleared, parent }))).push(Visit(Box.box({ elem: prepared.rendered, position: 0 }))), state, owner.key, prepared.routes, prepared.prepared, 0, done!)))
											},
										)
									},
								),
							)
						}
						_ => {
							# Keep the opaque descriptor across this helper boundary. Passing the
							# already-inspected structural union avoids a second inspection but
							# copies the large union and is slower with the pinned dev backend.
							built = lower_leaf!(current, $active_boundary, $routes, $boundaries)
							$root = built.root
							$routes = built.routes
							$boundaries = built.boundaries
						}
					}
				}
				CloseBoundary(boxed_boundary) => {
					boundary = Box.unbox(boxed_boundary)
					owner = boundary.owner
					cleared = boundary.cleared
					parent = boundary.parent
					remaining = $work
					built = { root: $root, routes: $routes, boundaries: $boundaries }
					$pending = Some(
						finish_rebuild!(
							owner,
							cleared,
							state,
							built,
							|finished| Work.next(
								|| {
									Host.component_exit!()
									Host.work_start!(3)
									lower_work!(remaining, state, (Box.unbox(parent)).key, finished.routes, { stored: finished.boundaries, active: parent }, finished.root, done!)
								},
							),
						),
					)
				}
				Append(builder) => Host.children_push!(builder, $root)
				OpenItem(key) => Host.scope_enter!(7, key.to_str(), 0)
				CloseItem(key) => {
					$root = Host.node_virtual_item!(key, $root)
					Host.scope_exit!()
				}
				CloseRow(builder, props) => {
					$root = finish_row!(builder, props)
					Host.scope_exit!()
				}
				CloseColumn(builder, props) => {
					$root = finish_column!(builder, props)
					Host.scope_exit!()
				}
				CloseKeyedColumn(builder, props, keys, revision) => {
					$root = finish_column!(builder, props)
					keyed_seed!($root, revision, keys)
					active = Box.unbox($boundaries.active)
					$boundaries = { stored: $boundaries.stored, active: Box.box({ ..active, keyed_container: $root, keyed_revision: revision, keyed_keys: keys }) }
					Host.scope_exit!()
				}
				ClosePanel(builder, props) => {
					$root = finish_panel!(builder, props)
					Host.scope_exit!()
				}
				CloseDialog(builder, props) => {
					$root = finish_dialog!(builder, props)
					route = { id: $root, boundary: $active_boundary, revision: (Box.unbox($boundaries.active)).revision, fire: |current, _| (props.on_dismiss)(current, {}) }
					$routes = Index.set($routes, route.id, route)
					$boundaries = record_route($boundaries, $active_boundary, route.id)
					Host.scope_exit!()
				}
				ClosePopover(builder, props) => {
					ids = finish_popover!(builder, props)
					$root = ids.id
					revision = (Box.unbox($boundaries.active)).revision
					match props.on_hover_enter {
						None => {}
						Some(handler) => {
							enter_route = { id: ids.hover_enter, boundary: $active_boundary, revision, fire: |current, _| handler(current, {}) }
							$routes = Index.set($routes, enter_route.id, enter_route)
							$boundaries = record_route($boundaries, $active_boundary, enter_route.id)
						}
					}
					match props.on_hover_exit {
						None => {}
						Some(handler) => {
							exit_route = { id: ids.hover_exit, boundary: $active_boundary, revision, fire: |current, _| handler(current, {}) }
							$routes = Index.set($routes, exit_route.id, exit_route)
							$boundaries = record_route($boundaries, $active_boundary, exit_route.id)
						}
					}
					Host.scope_exit!()
				}
				CloseScroll(props) => {
					$root = finish_scroll!($root, props)
					Host.scope_exit!()
				}
				CloseList(builder, props, first) => {
					match props.provider {
						None => {
							$root = finish_list!(builder, props, 0, 0)
						}
						Some(provider) => {
							$root = finish_list!(builder, props, first, $active_boundary)
							route = { id: $root, boundary: $active_boundary, revision: (Box.unbox($boundaries.active)).revision, fire: |current, _| rows_event!(provider, current) }
							$routes = Index.set($routes, route.id, route)
							$boundaries = record_route($boundaries, $active_boundary, route.id)
						}
					}
					Host.scope_exit!()
				}
			}
		}
		match $pending {
			Some(next) => next
			None => {
				result = { root: $root, routes: $routes, boundaries: $boundaries }
				remaining = $work
				current_owner = $active_boundary
				if remaining.is_empty() {
					Work.next(|| done!(result))
				} else {
					# Yield before consuming descendants: a calling closure may still
					# retain the input descriptor until this step returns.
					Work.next(|| lower_work!(remaining, state, current_owner, result.routes, result.boundaries, result.root, done!))
				}
			}
		}
	}

	# Ask the host which rows of a provided list to build. `instance` is the
	# list's own render boundary, whose lifetime carries its viewport.
	rows_window! : Elem.RowProvider(a), U32, U64 => { first : U64, end : U64 }
	rows_window! = |provider, row_height, instance| {
		request = match provider.scroll_to {
			None => { row: 0, align: 0, serial: 0 }
			Some(wanted) => {
				row: wanted.row,
				align: match wanted.align {
					Start => 1
					Center => 2
					End => 3
					Nearest => 4
				},
				serial: wanted.serial,
			}
		}
		window = Host.virtual_window!({ instance, count: provider.count, row_height, scroll_row: request.row, scroll_align: request.align, scroll_serial: request.serial })
		if window.first > window.end or window.end > provider.count {
			crash "host named rows outside a provided list"
		}
		window
	}

	# A viewport event either asks for the list's rows to be built again for a
	# new range, reports the range to the application, or both. The list's
	# boundary is transparent, so the application's action belongs to the list's
	# owner; when it changes nothing, a pending rebuild still happens.
	rows_event! : Elem.RowProvider(a), a => Action(a)
	rows_event! = |provider, current| {
		event = Host.virtual_rows_event!()
		fallback = if event.refresh Action.refresh else Action.none
		match provider.on_range {
			Some(handler) if event.report => {
				proposed = handler(current, { start: event.start, end: event.end })
				Action.deferred(
					|done| Action.resolve_work!(
						proposed,
						|resolved| match Action.inspect(resolved) {
							NoChange => done(fallback)
							_ => done(resolved)
						},
					),
				)
			}
			_ => fallback
		}
	}

	lower_leaf! : Elem(a), U64, Index(Route(a)), BuildingOwners(a) => Building(a)
	lower_leaf! = |elem, active_boundary, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = Host.node_text!(value)
			{ root: id, routes, boundaries }
		}
		StyledText(value) => {
			if value.style.font_size > max_style_value {
				crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
			}
			if value.style.font_weight != 0 and (value.style.font_weight < 100 or value.style.font_weight > 900) {
				crash "Gui font_weight is 0 for the native default, or 100 through 900"
			}
			id = Host.node_styled_text!({ value: value.value, fg: color(value.style.fg), font_size: value.style.font_size, font_weight: value.style.font_weight, font_face: font_face(value.style.font_face) })
			{ root: id, routes, boundaries }
		}
		ActionButton(button_value) => {
			style = style_args(button_value.style)
			hover_enter = match button_value.on_hover_enter {
				None => False
				Some(_) => True
			}
			hover_exit = match button_value.on_hover_exit {
				None => False
				Some(_) => True
			}
			ids = Host.node_action_button!({ caption: button_value.caption, label: button_value.label, enabled: button_value.enabled, hover_enter, hover_exit, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = {
				id: ids.id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, _| if button_value.enabled {
					(button_value.on_press)(current, {})
				} else {
					Action.none
				},
			}
			var $routes = Index.set(routes, route.id, route)
			var $boundaries = record_route(boundaries, active_boundary, route.id)
			match button_value.on_hover_enter {
				None => {}
				Some(handler) => {
					enter_route : Route(a)
					enter_route = { id: ids.hover_enter, boundary: active_boundary, revision: route.revision, fire: |current, _| if button_value.enabled handler(current, {}) else Action.none }
					$routes = Index.set($routes, enter_route.id, enter_route)
					$boundaries = record_route($boundaries, active_boundary, enter_route.id)
				}
			}
			match button_value.on_hover_exit {
				None => {}
				Some(handler) => {
					exit_route : Route(a)
					exit_route = { id: ids.hover_exit, boundary: active_boundary, revision: route.revision, fire: |current, _| if button_value.enabled handler(current, {}) else Action.none }
					$routes = Index.set($routes, exit_route.id, exit_route)
					$boundaries = record_route($boundaries, active_boundary, exit_route.id)
				}
			}
			{ root: ids.id, routes: $routes, boundaries: $boundaries }
		}
		Checkbox(checkbox_value) => {
			style = style_args(checkbox_value.style)
			id = Host.node_checkbox!({
				label: checkbox_value.label,
				checked: checkbox_value.checked,
				enabled: checkbox_value.enabled,
				box_bg: color(checkbox_value.box_bg),
				box_checked_bg: color(checkbox_value.box_checked_bg),
				box_border: color(checkbox_value.box_border),
				mark_color: color(checkbox_value.mark_color),
				gap: style.gap,
				padding_top: style.padding_top,
				padding_right: style.padding_right,
				padding_bottom: style.padding_bottom,
				padding_left: style.padding_left,
				width_kind: style.width_kind,
				width: style.width,
				height_kind: style.height_kind,
				height: style.height,
				min_width_kind: style.min_width_kind,
				min_width: style.min_width,
				min_height_kind: style.min_height_kind,
				min_height: style.min_height,
				max_width_kind: style.max_width_kind,
				max_width: style.max_width,
				max_height_kind: style.max_height_kind,
				max_height: style.max_height,
				grow: style.grow,
				bg: style.bg,
				hover_bg: style.hover_bg,
				active_bg: style.active_bg,
				disabled_bg: style.disabled_bg,
				disabled_fg: style.disabled_fg,
				focus_color: style.focus_color,
				fg: style.fg,
				border_color: style.border_color,
				border_top: style.border_top,
				border_right: style.border_right,
				border_bottom: style.border_bottom,
				border_left: style.border_left,
				radius: style.radius,
				font_size: style.font_size,
				font_weight: style.font_weight,
				shadow: style.shadow,
				shadow_y: style.shadow_y,
				shadow_color: style.shadow_color,
				shadow_alpha: style.shadow_alpha,
				font_face: style.font_face,
				text_overflow: style.text_overflow,
				overflow_x: style.overflow_x,
				overflow_y: style.overflow_y,
				align: style.align,
				justify: style.justify,
			})
			route = {
				id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, _| if checkbox_value.enabled {
					(checkbox_value.on_change)(current, { checked: !checkbox_value.checked })
				} else {
					Action.none
				},
			}
			{ root: id, routes: Index.set(routes, route.id, route), boundaries: record_route(boundaries, active_boundary, route.id) }
		}
		Textarea(textarea_value) => {
			style = style_args(textarea_value.style)
			id = Host.node_textarea!({ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = {
				id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, input| if textarea_value.enabled and !textarea_value.read_only {
					(textarea_value.on_input)(current, { value: input })
				} else {
					Action.none
				},
			}
			{ root: id, routes: Index.set(routes, route.id, route), boundaries: record_route(boundaries, active_boundary, route.id) }
		}
		Image(image_value) => {
			style = style_args(image_value.style)
			format = match image_value.format {
				Bmp => 0
				Gif => 1
				Jpeg => 2
				Png => 3
				Svg => 4
				Tiff => 5
				Webp => 6
			}
			fit = match image_value.fit {
				Contain => 0
				Cover => 1
				Fill => 2
				None => 3
				ScaleDown => 4
			}
			id = Host.node_image!({ label: image_value.label, bytes: image_value.bytes, format, fit, grayscale: image_value.grayscale, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			{ root: id, routes, boundaries }
		}
		Canvas(canvas_value) => {
			width = length(canvas_value.style.width)
			height = length(canvas_value.style.height)
			primitives = canvas_value.primitives.map(
				|primitive| match primitive {
					Ellipse(shape) => { kind: 0, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0, text: "", text_size: 0, align: 0 }
					Line(shape) => { kind: 1, key: shape.key, label: shape.label, x: shape.x1, y: shape.y1, width: 0, height: 0, x2: shape.x2, y2: shape.y2, fill: color(Default), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0, text: "", text_size: 0, align: 0 }
					Rectangle(shape) => { kind: 2, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: shape.radius, text: "", text_size: 0, align: 0 }
					Text(shape) => {
						text_align = match shape.align {
							Start => 0
							Center => 1
							End => 2
						}
						{ kind: 3, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: 0, x2: 0, y2: 0, fill: color(shape.color), stroke: color(Default), stroke_width: 0, radius: 0, text: shape.value, text_size: shape.size, align: text_align }
					}
				},
			)
			hover = match canvas_value.on_hover {
				Some(_) => True
				None => False
			}
			wheel = match canvas_value.on_wheel {
				Some(_) => True
				None => False
			}
			id = Host.node_canvas!({ label: canvas_value.label, primitives, width_kind: width.kind, width: width.value, height_kind: height.kind, height: height.value, grow: canvas_value.style.grow, bg: color(canvas_value.style.bg), border_color: color(canvas_value.style.border_color), border_width: canvas_value.style.border_width, radius: canvas_value.style.radius, hover, wheel })
			route = {
				id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, _| {
					event = Host.canvas_event!()
					target = match event.target {
						0 => None
						value => Some(value)
					}
					match event.phase {
						0 => (canvas_value.on_pointer)(current, { phase: Begin, x: event.x, y: event.y, target })
						1 => (canvas_value.on_pointer)(current, { phase: Move, x: event.x, y: event.y, target })
						2 => (canvas_value.on_pointer)(current, { phase: End, x: event.x, y: event.y, target })
						3 => match canvas_value.on_hover {
							Some(handler) => handler(current, { phase: Move, x: event.x, y: event.y, target })
							None => crash "canvas hover delivered without a hover handler"
						}
						4 => match canvas_value.on_hover {
							Some(handler) => handler(current, { phase: Leave, x: event.x, y: event.y, target })
							None => crash "canvas hover delivered without a hover handler"
						}
						5 => match canvas_value.on_wheel {
							Some(handler) => handler(current, { x: event.x, y: event.y, dx: event.dx, dy: event.dy, target })
							None => crash "canvas wheel delivered without a wheel handler"
						}
						_ => crash "invalid canvas pointer phase"
					}
				},
			}
			{ root: id, routes: Index.set(routes, route.id, route), boundaries: record_route(boundaries, active_boundary, route.id) }
		}
		TextInput(input_value) => {
			style = style_args(input_value.style)
			ids = Host.node_text_input!({ label: input_value.label, value: input_value.value, placeholder: input_value.placeholder, enabled: input_value.enabled, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			change_route : Route(a)
			change_route = {
				id: ids.change,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, input| if input_value.enabled {
					(input_value.on_change)(current, { value: input })
				} else {
					Action.none
				},
			}
			submit_route : Route(a)
			submit_route = {
				id: ids.submit,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, input| if input_value.enabled {
					(input_value.on_submit)(current, { value: input })
				} else {
					Action.none
				},
			}
			{ root: ids.id, routes: Index.set(Index.set(routes, change_route.id, change_route), submit_route.id, submit_route), boundaries: record_route(record_route(boundaries, active_boundary, change_route.id), active_boundary, submit_route.id) }
		}

		_ => crash "container sent to leaf lowering"
	}

	revision : Index(BoundaryInfo(a)), U64 -> U64
	revision = |boundaries, key| (Index.get(boundaries, key) ?? crash "missing route owner").revision

	record_route : BuildingOwners(a), U64, U64 -> BuildingOwners(a)
	record_route = |boundaries, key, id| {
		owner = Box.unbox(boundaries.active)
		if owner.key != key {
			crash "mismatched route owner"
		}
		{ stored: boundaries.stored, active: Box.box({ ..owner, route_ids: RouteIds.append(owner.route_ids, id) }) }
	}

	unchanged! : BoundaryInfo(a), a, (Bool -> Work) => Work
	unchanged! = |owner, state, done!| match owner.memo {
		Unknown => done!(False)
		Known(boxed) => Work.next(
			|| {
				Host.work_start!(4)
				Host.component_work!(1, 1)
				compare! = Box.unbox(boxed)
				compare!(
					state,
					|result| Work.next(
						|| {
							Host.work_end!(4)
							if result {
								Host.component_work!(2, 1)
							}
							done!(result)
						},
					),
				)
			},
		)
	}

	prepare_component! : Elem.BoundComponent(a), a, U64, Index(Route(a)), BuildingOwners(a), ([Retained(Building(a)), Descend(BoundaryInfo(a), Box(BuildingOwner(a)))] -> Work) => Work
	prepare_component! = |bound, state, parent, routes, boundaries, done!| {
		Host.work_end!(3)
		Host.work_start!(0)
		resolved = match bound.key {
			None => Host.component_resolve!(0, [])
			Some(key) => Host.component_resolve!(1, Key.to_bytes(key))
		}
		Host.component_work!(5, 1)
		prior = Index.get(boundaries.stored, resolved.instance)
		parent_info = Box.unbox(boundaries.active)
		if parent_info.key != parent {
			crash "mismatched component parent"
		}
		owner = match prior {
			Ok(previous) => {
				was_memoized = match previous.bound {
					None => False
					Some(old) => match old.remember {
						None => False
						Some(_) => True
					}
				}
				is_memoized = match bound.remember {
					None => False
					Some(_) => True
				}
				{ ..previous, bound: Some(bound), render: bound.render, memo: if was_memoized == is_memoized previous.memo else Unknown }
			}
			Err(_) => {
				Host.component_work!(3, 1)
				{ key: resolved.instance, parent: Some(parent), path: parent_info.path.append(resolved.instance), render: bound.render, root: 0, bound: Some(bound), memo: Unknown, revision: 0, route_ids: RouteIds.empty, children: [], keyed_container: 0, keyed_revision: 0, keyed_items: KeyedSeq.empty, keyed: None }
			}
		}
		with_parent = Box.box({ ..parent_info, children: parent_info.children.append(resolved.instance) })
		check! = bound.exists
		Work.next(
			|| check!(
				state,
				|present| Work.next(
					|| {
						if !present {
							crash "render emitted a removed component"
						}
						Host.work_end!(0)
						unchanged!(
							owner,
							state,
							|same| Work.next(
								|| {
									if same {
										Host.work_start!(3)
										root = Host.retain_subtree!(owner.root)
										done!(Retained({ root, routes, boundaries: { stored: Index.set(boundaries.stored, owner.key, owner), active: with_parent } }))
									} else {
										done!(Descend(owner, with_parent))
									}
								},
							),
						)
					},
				),
			),
		)
	}

	retire! : U64, Index(Route(a)), Index(BoundaryInfo(a)) => { routes : Index(Route(a)), boundaries : Index(BoundaryInfo(a)) }
	retire! = |key, routes, boundaries| {
		var $work = [Visit(key)]
		var $routes = routes
		var $boundaries = boundaries
		while !$work.is_empty() {
			item = $work.last() ?? crash "missing retirement work"
			$work = $work.drop_last(1)
			match item {
				Visit(current) => {
					owner = Index.get($boundaries, current) ?? crash "missing retired component"
					$work = $work.append(Remove(current))
					for keyed_item in KeyedSeq.to_list(owner.keyed_items) {
						$work = $work.append(Visit(keyed_item.value))
					}
					var $index = owner.children.len()
					while $index > 0 {
						$index = $index - 1
						$work = $work.append(Visit(owner.children.get($index) ?? crash "missing retired child"))
					}
				}
				Remove(current) => {
					owner = Index.get($boundaries, current) ?? crash "missing retired component"
					$routes = RouteIds.fold(owner.route_ids, $routes, |remaining, id| Index.remove(remaining, id))
					Host.component_work!(4, 1)
					$boundaries = Index.remove($boundaries, current)
				}
			}
		}
		{ routes: $routes, boundaries: $boundaries }
	}

	keyed_instance = |items, wanted| {
		match KeyedSeq.get(items, wanted) {
			Ok(instance) => Some(instance)
			Err(_) => None
		}
	}

	keyed_without! = |items, unwanted| {
		changed = KeyedSeq.remove(items, unwanted) ?? crash "keyed removal target missing"
		Host.component_work!(9, KeyedSeq.last_visits(changed))
		changed
	}

	keyed_place! = |items, item, placement| match placement {
		End => {
			changed = KeyedSeq.insert_before(items, item.key, item.instance, End) ?? crash "keyed insertion failed"
			Host.component_work!(9, KeyedSeq.last_visits(changed))
			changed
		}
		Before(anchor) => {
			changed = KeyedSeq.insert_before(items, item.key, item.instance, Before(anchor)) ?? crash "keyed insertion failed"
			Host.component_work!(9, KeyedSeq.last_visits(changed))
			changed
		}
	}

	# Lower only values carried by Insert and Set. The resulting root already is
	# the item's boundary root and is passed to the host transaction unchanged.
	keyed_lower! = |elem, owner, state, routes, boundaries, done!| {
		active = { key: owner.key, revision: owner.revision, path: owner.path, route_ids: RouteIds.empty, children: [], keyed_container: 0, keyed_revision: 0, keyed_keys: [], keyed: None }
		lower!(
			elem,
			state,
			owner.key,
			routes,
			{ stored: boundaries, active: Box.box(active) },
			0,
			|lowered| {
				built = Box.unbox(lowered.boundaries.active)
				instance = built.children.get(0) ?? crash "keyed item did not lower to a component boundary"
				if built.children.len() != 1 {
					crash "keyed item must lower to exactly one component boundary"
				}
				Work.next(|| done!({ instance, root: lowered.root, routes: lowered.routes, boundaries: lowered.boundaries.stored }))
			},
		)
	}

	keyed_steps! = |steps, owner, state, routes, boundaries, items, native, done!| if steps.is_empty() {
		Work.next(|| done!({ routes, boundaries, items, native }))
	} else {
		step = steps.first() ?? crash "missing keyed step"
		rest = steps.drop_first(1)
		match step {
			KeyedMove(key, placement) => {
				keyed_move_before!(key, placement)
				next_items = KeyedSeq.move_before(items, key, placement) ?? crash "keyed move target missing"
				Host.component_work!(9, KeyedSeq.last_visits(next_items))
				Work.next(|| keyed_steps!(rest, owner, state, routes, boundaries, next_items, native, done!))
			}
			KeyedRemove(key) => {
				keyed_remove!(key)
				instance = match keyed_instance(items, key) {
					Some(found) => found
					None => crash "keyed remove target missing"
				}
				retired = retire!(instance, routes, boundaries)
				Work.next(|| keyed_steps!(rest, owner, state, retired.routes, retired.boundaries, keyed_without!(items, key), native, done!))
			}
			KeyedInsert(key, elem, placement) => keyed_lower!(
				Box.unbox(elem),
				owner,
				state,
				routes,
				boundaries,
				|built| {
					keyed_insert_before!(key, placement, built.root)
					next_items = keyed_place!(items, { key, instance: built.instance }, placement)
					Work.next(|| keyed_steps!(rest, owner, state, built.routes, built.boundaries, next_items, native, done!))
				},
			)
			KeyedSet(key, elem) => {
				old_instance = match keyed_instance(items, key) {
					Some(found) => found
					None => crash "keyed set target missing"
				}
				keyed_lower!(
					Box.unbox(elem),
					owner,
					state,
					routes,
					boundaries,
					|built| {
						if built.instance != old_instance {
							crash "keyed set changed item boundary identity"
						}
						keyed_set!(key, built.root)
						Work.next(|| keyed_steps!(rest, owner, state, built.routes, built.boundaries, items, native, done!))
					},
				)
			}
		}
	}

	emit_keyed_native! = |native| for edit in native {
		match edit {
			NativeInsert(key, placement, root) => keyed_insert_before!(key, placement, root)
			NativeMove(key, placement) => keyed_move_before!(key, placement)
			NativeRemove(key) => keyed_remove!(key)
			NativeSet(key, root) => keyed_set!(key, root)
		}
	}

	keyed_descriptor_steps : List(Elem.KeyedOperation), List(Key), List(Elem(a)) -> List(KeyedStep(a))
	keyed_descriptor_steps = |operations, keys, children| {
		var $steps = []
		var $child_index = 0
		for operation in operations {
			match operation {
				KeyedInsert(key, placement) => {
					child = children.get($child_index) ?? crash "keyed insert child missing"
					expected = keys.get($child_index) ?? crash "keyed insert key missing"
					if expected != key {
						crash "keyed insert child key mismatch"
					}
					$steps = $steps.append(KeyedInsert(key, Box.box(child), placement))
					$child_index = $child_index + 1
				}
				KeyedSet(key) => {
					child = children.get($child_index) ?? crash "keyed set child missing"
					expected = keys.get($child_index) ?? crash "keyed set key missing"
					if expected != key {
						crash "keyed set child key mismatch"
					}
					$steps = $steps.append(KeyedSet(key, Box.box(child)))
					$child_index = $child_index + 1
				}
				KeyedMove(key, placement) => {
					$steps = $steps.append(KeyedMove(key, placement))
				}
				KeyedRemove(key) => {
					$steps = $steps.append(KeyedRemove(key))
				}
			}
		}
		if $child_index != children.len() {
			crash "unused keyed descriptor children"
		}
		$steps
	}

	# The first eight digest bytes address a bucket; full keys settle collisions.
	key_bucket : Key -> U64
	key_bucket = |key| {
		bytes = Key.to_bytes(key)
		var $value = 0.U64
		var $offset = 0.U64
		while $offset < 8 {
			byte = bytes.get($offset) ?? crash "key digest was not 32 bytes"
			$value = $value * 256 + byte.to_u64()
			$offset = $offset + 1
		}
		$value
	}

	keyed_fallback_steps : KeyedSeq(U64), List(Key), List(Elem(a)) -> List(KeyedStep(a))
	keyed_fallback_steps = |old_items, keys, children| {
		# Index the surviving keys once; scanning the key list per resident
		# item made the snapshot fallback quadratic in collection size.
		var $survivors = Index.empty
		for key in keys {
			bucket = key_bucket(key)
			entries = Index.get($survivors, bucket) ?? []
			$survivors = Index.set($survivors, bucket, entries.append(key))
		}
		var $steps = []
		for old in KeyedSeq.to_list(old_items) {
			var $present = False
			entries = Index.get($survivors, key_bucket(old.key)) ?? []
			for key in entries {
				if key == old.key {
					$present = True
				}
			}
			if !$present {
				$steps = $steps.append(KeyedRemove(old.key))
			}
		}
		if keys.len() != children.len() {
			crash "keyed fallback key count differs from children"
		}
		var $index = keys.len()
		var $placement = End
		while $index > 0 {
			$index = $index - 1
			key = keys.get($index) ?? crash "keyed fallback key missing"
			child = children.get($index) ?? crash "keyed fallback child missing"
			match keyed_instance(old_items, key) {
				Some(_) => {
					$steps = $steps.append(KeyedMove(key, $placement))
					$steps = $steps.append(KeyedSet(key, Box.box(child)))
				}
				None => {
					$steps = $steps.append(KeyedInsert(key, Box.box(child), $placement))
				}
			}
			$placement = Before(key)
		}
		$steps
	}

	update_keyed! : BoundaryInfo(a), Elem.Frame, a, [None, Some(Box(Action.Worker(a)))], U64, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => Work
	update_keyed! = |owner, props, state, task, task_owner, render, routes, boundaries| {
		Host.work_start!(2)
		Host.component_work!(0, 1)
		render! = owner.render
		render!(
			state,
			|rendered| Work.next(
				|| {
					Host.work_end!(2)
					Host.work_start!(3)
					descriptor = match Elem.inspect(rendered) {
						KeyedColumn(value) => value
						_ => crash "keyed boundary rendered a non-keyed element"
					}
					planned = if descriptor.base_revision == owner.keyed_revision {
						{ base: descriptor.base_revision, revision: descriptor.revision, steps: keyed_descriptor_steps(descriptor.operations, descriptor.keys, descriptor.children) }
					} else {
						full = (Box.unbox(descriptor.full))({})
						{ base: owner.keyed_revision, revision: descriptor.revision, steps: keyed_fallback_steps(owner.keyed_items, full.keys, full.children) }
					}
					Host.begin_render!(owner.key)
					keyed_edit_begin!(owner.keyed_container, planned.base, planned.revision)
					# Match the native column scope used by the initial mount so keyed item
					# digests resolve to their existing boundary instances after moves.
					Host.scope_enter!(2, props.label, 0)
					keyed_steps!(
						planned.steps,
						owner,
						state,
						routes,
						boundaries,
						owner.keyed_items,
						[],
						|built| Work.flush(
							|| {
								Host.work_end!(3)
								Host.work_start!(0)
								Host.scope_exit!()
								keyed_edit_commit!()
								updated = { ..owner, children: [], keyed_revision: planned.revision, keyed_items: built.items, memo: Unknown }
								match task {
									None => {}
									Some(worker) => enqueue_work!(task_owner, worker)
								}
								Host.work_end!(0)
								install!(state, render, built.routes, Index.set(built.boundaries, owner.key, updated))
								Work.done
							},
						),
					)
				},
			),
		)
	}

	rebuild! : BoundaryInfo(a), a, Index(Route(a)), Index(BoundaryInfo(a)), (Lowered(a) -> Work) => Work
	rebuild! = |owner, state, routes, boundaries, done!| prepare_rebuild!(
		owner,
		state,
		routes,
		boundaries,
		|prepared| {
			# The completion must not retain the rendered descriptor through lowering.
			cleared = prepared.cleared
			Work.next(|| lower!(prepared.rendered, state, owner.key, prepared.routes, prepared.prepared, 0, |lowered| Work.next(|| finish_rebuild!(owner, cleared, state, lowered, done!))))
		},
	)

	prepare_rebuild! = |owner, state, routes, boundaries, done!| {
		Host.work_start!(0)
		var $routes = routes
		$routes = RouteIds.fold(owner.route_ids, $routes, |current, id| Index.remove(current, id))
		cleared = { ..owner, revision: owner.revision + 1, route_ids: RouteIds.empty, children: [], memo: Unknown }
		# Keep growing metadata out of the persistent index until this owner is
		# complete; per-route publication shares and repeatedly copies its lists.
		prepared = { stored: boundaries, active: Box.box({ key: cleared.key, revision: cleared.revision, path: cleared.path, route_ids: RouteIds.empty, children: [], keyed_container: 0, keyed_revision: 0, keyed_keys: [], keyed: None }) }
		Host.work_end!(0)
		Host.work_start!(2)
		Host.component_work!(0, 1)
		render! = owner.render
		remaining_routes = $routes
		Work.next(
			|| render!(
				state,
				|rendered| Work.next(
					|| {
						Host.work_end!(2)
						Host.work_start!(3)
						done!({ cleared, rendered, routes: remaining_routes, prepared })
					},
				),
			),
		)
	}

	finish_rebuild! = |owner, cleared, state, lowered, done!| {
		completed = Box.unbox(lowered.boundaries.active)
		var $keyed_items = KeyedSeq.empty
		var $keyed_index = 0.U64
		for key in completed.keyed_keys {
			instance = completed.children.get($keyed_index) ?? crash "keyed item boundary missing"
			$keyed_items = KeyedSeq.insert_before($keyed_items, key, instance, End) ?? crash "duplicate keyed item boundary"
			$keyed_index = $keyed_index + 1
		}
		keyed_meta = if completed.keyed_container == 0 {
			{ container: cleared.keyed_container, revision: cleared.keyed_revision, items: cleared.keyed_items }
		} else {
			{ container: completed.keyed_container, revision: completed.keyed_revision, items: $keyed_items }
		}
		root = if owner.key == 0 lowered.root else Host.node_boundary!(owner.key, lowered.root)
		Host.work_end!(3)
		Host.work_start!(0)
		current = {
			..cleared,
			route_ids: completed.route_ids,
			children: if completed.keyed_container == 0 completed.children else [],
			keyed_container: keyed_meta.container,
			keyed_revision: keyed_meta.revision,
			keyed_items: keyed_meta.items,
			keyed: match completed.keyed {
				Some(value) => Some(value)
				None => cleared.keyed
			},
		}
		var $settled_routes = lowered.routes
		var $settled_boundaries = lowered.boundaries.stored
		# Retirement needs the live-child set only when a previous child can
		# actually be missing; an initial mount or an unchanged child list —
		# the common full-root case — retires nothing and builds no index.
		if !owner.children.is_empty() and owner.children != current.children {
			var $live = Index.empty
			for child in current.children {
				$live = Index.set($live, child, True)
			}
			for previous in owner.children {
				match Index.get($live, previous) {
					Ok(_) => {}
					Err(_) => {
						retired = retire!(previous, $settled_routes, $settled_boundaries)
						$settled_routes = retired.routes
						$settled_boundaries = retired.boundaries
					}
				}
			}
		}
		settled_routes = $settled_routes
		settled_boundaries = $settled_boundaries
		finish! = |memo| Work.next(
			|| {
				updated = { ..current, root, memo }
				Host.work_end!(0)
				done!({ root, routes: settled_routes, boundaries: Index.set(settled_boundaries, owner.key, updated) })
			},
		)
		match owner.bound {
			None => finish!(Unknown)
			Some(bound) => match bound.remember {
				None => finish!(Unknown)
				Some(capture!) => Work.next(|| capture!(state, |snapshot| Work.next(|| finish!(Known(snapshot)))))
			}
		}
	}

	exists! : Index(BoundaryInfo(a)), U64, a, (Bool -> Work) => Work
	exists! = |boundaries, key, state, done!| match Index.get(boundaries, key) {
		Err(_) => Work.next(|| done!(False))
		Ok(owner) => match owner.bound {
			None => Work.next(|| done!(True))
			Some(bound) => Work.next(
				|| {
					check! = bound.exists
					check!(state, done!)
				},
			)
		}
	}

	# Flush executed projection counters before the transaction commits. The
	# trampoline owns these counts; constructing a deferred thunk counts nothing.
	run_work! = |work| Work.run!(
		work,
		|gets, sets| {
			if gets > 0 {
				Host.component_work!(7, gets)
			}
			if sets > 0 {
				Host.component_work!(8, sets)
			}
		},
	)

	apply_action! : Action(a), a, U64, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => Work
	apply_action! = |action, state, origin, render, routes, boundaries| match Action.inspect(action) {
		NoChange => Work.flush(
			|| {
				Host.apply!(NoChange)
				install!(state, render, routes, boundaries)
				Work.done
			},
		)
		Deferred(_) => Work.next(|| Action.resolve_work!(action, |resolved| Work.next(|| apply_action!(resolved, state, origin, render, routes, boundaries))))
		_ => {
			source = Index.get(boundaries, origin) ?? crash "missing action owner"
			levels = Action.owner_levels(action)
			# A refresh renders its own boundary again and changes no state, so no
			# ancestor snapshot is invalidated. Every other action changes state,
			# which a transparent boundary does not hold: it passes to the nearest
			# boundary above that does. An action's levels count the boundaries it
			# was delegated through, and a transparent boundary never adapts one,
			# so levels are counted over the boundaries that hold state: a row of a
			# list delegates to its owner's parent exactly as if it had been built
			# in the owner.
			changes_state = match Action.inspect(action) {
				Refresh => False
				_ => True
			}
			is_transparent = |offset| transparent(boundaries, source.path.get(offset) ?? crash "missing delegated owner")
			var $offset = if levels >= source.path.len() 0 else source.path.len() - levels - 1
			if changes_state {
				$offset = source.path.len() - 1
				while $offset > 0 and is_transparent($offset) {
					$offset = $offset - 1
				}
				var $remaining = levels
				while $remaining > 0 and $offset > 0 {
					$offset = $offset - 1
					while $offset > 0 and is_transparent($offset) {
						$offset = $offset - 1
					}
					$remaining = $remaining - 1
				}
			}
			owner = source.path.get($offset) ?? crash "missing delegated owner"
			target = Index.get(boundaries, owner) ?? crash "missing delegated component"
			var $dirty = boundaries
			if changes_state {
				for key in target.path {
					info = Index.get($dirty, key) ?? crash "missing update ancestor"
					if key != owner {
						$dirty = Index.set($dirty, key, { ..info, memo: Unknown })
						Host.component_work!(6, 1)
					}
				}
			}
			match Action.inspect(action) {
				Refresh => update_boundary!(state, None, owner, owner, render, routes, $dirty)
				Update(next) => update_boundary!(next, None, owner, owner, render, routes, $dirty)
				Delegate(next) => update_boundary!(next, None, 0, 0, render, routes, $dirty)
				Task(task) => update_boundary!(task.pending, Some(task.run), owner, owner, render, routes, $dirty)
				_ => crash "action changed during dispatch"
			}
		}
	}

	transparent : Index(BoundaryInfo(a)), U64 -> Bool
	transparent = |boundaries, key| match Index.get(boundaries, key) {
		Err(_) => False
		Ok(info) => match info.bound {
			None => False
			Some(bound) => bound.transparent
		}
	}

	enqueue_work! = |owner, worker| Host.enqueue_task!(
		owner,
		Box.box(
			|| Action.worker_work!(
				worker,
				|completion| Work.next(
					|| {
						Host.task_complete!(completion)
						Work.done
					},
				),
			),
		),
	)

	update_boundary! : a, [None, Some(Box(Action.Worker(a)))], U64, U64, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => Work
	update_boundary! = |state, task, task_owner, render_owner, render, routes, boundaries| {
		owner = Index.get(boundaries, render_owner) ?? crash "missing render owner"
		keyed = match owner.keyed {
			Some(keyed_props) => Some(keyed_props)
			None => None
		}
		match keyed {
			Some(value) => update_keyed!(owner, value, state, task, task_owner, render, routes, boundaries)
			None => unchanged!(
				owner,
				state,
				|same| Work.next(
					|| {
						if same {
							Work.flush(
								|| {
									Host.apply!(NoChange)
									match task {
										None => {}
										Some(worker) => enqueue_work!(task_owner, worker)
									}
									install!(state, render, routes, boundaries)
									Work.done
								},
							)
						} else {
							Host.begin_render!(render_owner)
							rebuild!(
								owner,
								state,
								routes,
								boundaries,
								|lowered| Work.flush(
									|| {
										Host.apply!(Replace({ old_root: owner.root, root: lowered.root }))
										match task {
											None => {}
											Some(worker) => enqueue_work!(task_owner, worker)
										}
										install!(state, render, lowered.routes, lowered.boundaries)
										Work.done
									},
								),
							)
						}
					},
				),
			)
		}
	}

	install! : a, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => {}
	install! = |state, render, routes, boundaries| {
		discard! = || Work.flush(
			|| {
				Host.apply!(NoChange)
				install!(state, render, routes, boundaries)
				Work.done
			},
		)
		dispatch! = |input| {
			work = match Session.inspect(input) {
				Event(id) => {
					Host.work_start!(0)
					Host.component_work!(5, 1)
					found = Index.get(routes, id)
					Host.work_end!(0)
					match found {
						Ok(route) => exists!(
							boundaries,
							route.boundary,
							state,
							|present| Work.next(
								|| {
									if present and route.revision == revision(boundaries, route.boundary) {
										Host.work_start!(1)
										action = (route.fire)(state, Host.input_value!())
										Action.resolve_work!(
											action,
											|resolved| Work.next(
												|| {
													Host.work_end!(1)
													apply_action!(resolved, state, route.boundary, render, routes, boundaries)
												},
											),
										)
									} else {
										discard!()
									}
								},
							),
						)
						Err(_) => discard!()
					}
				}
				Completion(completed) => exists!(
					boundaries,
					completed.owner,
					state,
					|present| Work.next(
						|| {
							if present {
								Host.work_start!(1)
								Action.complete_work!(
									completed.resume,
									state,
									|action| Work.next(
										|| Action.resolve_work!(
											action,
											|resolved| Work.next(
												|| {
													Host.work_end!(1)
													apply_action!(resolved, state, completed.owner, render, routes, boundaries)
												},
											),
										),
									),
								)
							} else {
								discard!()
							}
						},
					),
				)
			}
			run_work!(work)
		}
		Host.set_dispatch!(Box.box(dispatch!))
	}

	start! : a, (a -> Elem(a)), { title : Str, width : U32, height : U32, background : Style.Color, foreground : Style.Color } => {}
	start! = |initial, render, window| {
		Host.window_config!(window.title, window.width, window.height, color(window.background), color(window.foreground))
		root = { key: 0, parent: None, path: [0], render: |state, done!| Work.next(|| done!(render(state))), root: 0, bound: None, memo: Unknown, revision: 0, route_ids: RouteIds.empty, children: [], keyed_container: 0, keyed_revision: 0, keyed_items: KeyedSeq.empty, keyed: None }
		Host.begin_render!(0)
		run_work!(
			rebuild!(
				root,
				initial,
				Index.empty,
				Index.empty,
				|lowered| Work.flush(
					|| {
						Host.apply!(Mount({ root: lowered.root }))
						install!(initial, render, lowered.routes, lowered.boundaries)
						Work.done
					},
				),
			),
		)
	}
}
