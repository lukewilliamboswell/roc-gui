import Host
import Action
import Elem
import Key
import Gui
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
	}

	Lowered(a) : {
		boundaries : Index(BoundaryInfo(a)),
		root : U64,
		routes : Index(Route(a)),
	}

	BuildingOwner : { key : U64, revision : U64, path : List(U64), route_ids : RouteIds, children : List(U64) }

	# Keep active owner metadata compact in the explicit lowering work stack.
	BuildingOwners(a) : { stored : Index(BoundaryInfo(a)), active : Box(BuildingOwner) }

	Building(a) : { boundaries : BuildingOwners(a), root : U64, routes : Index(Route(a)) }

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
		style = style_args(props)
		Host.node_row!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_column! = |builder, props| {
		style = style_args(props)
		Host.node_column!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_dialog! = |builder, props| {
		style = style_args(props)
		Host.node_dialog!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_panel! = |builder, props| {
		style = style_args(props)
		Host.node_panel!({ builder, label: props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
	}

	finish_scroll! = |child, props| {
		axis = match props.axis {
			Vertical => 0
			Horizontal => 1
			Both => 2
		}
		style = style_args(props)
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

	finish_list! = |builder, props| {
		style = style_args(props)
		id = Host.node_virtual_list!({
			builder,
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
	LowerWork(a) : [
		Visit(Elem(a), U64),
		Append(U64),
		CloseRow(U64, Elem.RowProps),
		CloseColumn(U64, Elem.ColProps),
		CloseDialog(U64, Elem.DialogProps(a)),
		ClosePanel(U64, Elem.PanelProps),
		CloseScroll(Elem.ScrollProps(a)),
		CloseList(U64, Elem.VirtualListProps(a)),
		OpenItem(U64),
		CloseItem(U64),
		CloseBoundary(BoundaryInfo(a), BoundaryInfo(a), Box(BuildingOwner)),
	]

	queue_children : WorkStack(LowerWork(a)), List(Elem(a)), U64 -> WorkStack(LowerWork(a))
	queue_children = |work, children, builder| {
		var $work = work
		var $position = children.len()
		while $position > 0 {
			$position = $position - 1
			child = children.get($position) ?? crash "missing traversal child"
			$work = $work.push(Append(builder)).push(Visit(child, $position))
		}
		$work
	}

	lower! : Elem(a), a, U64, Index(Route(a)), BuildingOwners(a), U64, (Building(a) -> Work) => Work
	lower! = |elem, state, active_boundary, routes, boundaries, position, done!| lower_work!(WorkStack.empty.push(Visit(elem, position)), state, active_boundary, routes, boundaries, 0, done!)

	lower_work! = |work, state, active_boundary, routes, boundaries, root, done!| {
		var $work = work
		var $routes = routes
		var $boundaries = boundaries
		var $root = root
		var $pending = None
		var $visited = False
		var $active_boundary = active_boundary
		while !$visited and !$work.is_empty() and (match $pending {
			None => True
			Some(_) => False
		}) {
			frame = $work.pop() ?? crash "missing lowering work"
			$visited = True
			$work = frame.rest
			match frame.item {
				Visit(current, child_position) => match Elem.inspect(current) {
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
					Dialog(value) => {
						Host.scope_enter!(4, value.props.label, child_position)
						builder = Host.children_begin!()
						$work = queue_children($work.push(CloseDialog(builder, value.props)), value.children, builder)
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
						$work = $work.push(CloseScroll({ ..value, content: Elem.text("") })).push(Visit(value.content, 0))
					}
					VirtualList(value) => {
						Host.scope_enter!(6, value.label, child_position)
						builder = Host.children_begin!()
						$work = $work.push(CloseList(builder, { ..value, items: [] }))
						var $index = value.items.len()
						while $index > 0 {
							$index = $index - 1
							row = value.items.get($index) ?? crash "missing virtual row"
							$work = $work.push(Append(builder)).push(CloseItem(row.key)).push(Visit(row.content, 0)).push(OpenItem(row.key))
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
											prepare_rebuild!(owner, state, saved_routes, saved_boundaries.stored, |prepared| Work.next(|| lower_work!(remaining.push(CloseBoundary(owner, prepared.cleared, parent)).push(Visit(prepared.rendered, 0)), state, owner.key, prepared.routes, prepared.prepared, 0, done!)))
										},
									)
								},
							),
						)
					}
					_ => {
						built = lower_leaf!(current, $active_boundary, $routes, $boundaries)
						$root = built.root
						$routes = built.routes
						$boundaries = built.boundaries
					}
				}
				CloseBoundary(owner, cleared, parent) => {
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
				CloseScroll(props) => {
					$root = finish_scroll!($root, props)
					Host.scope_exit!()
				}
				CloseList(builder, props) => {
					$root = finish_list!(builder, props)
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

	lower_leaf! : Elem(a), U64, Index(Route(a)), BuildingOwners(a) => Building(a)
	lower_leaf! = |elem, active_boundary, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = Host.node_text!(value)
			{ root: id, routes, boundaries }
		}
		StyledText(value) => {
			if value.font_size > max_style_value {
				crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
			}
			if value.font_weight != 0 and (value.font_weight < 100 or value.font_weight > 900) {
				crash "Gui font_weight is 0 for the native default, or 100 through 900"
			}
			id = Host.node_styled_text!({ value: value.value, fg: color(value.fg), font_size: value.font_size, font_weight: value.font_weight, font_face: font_face(value.font_face) })
			{ root: id, routes, boundaries }
		}
		ActionButton(button_value) => {
			style = style_args(button_value)
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
			style = style_args(checkbox_value)
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
			style = style_args(textarea_value)
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
			style = style_args(image_value)
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
			width = length(canvas_value.width)
			height = length(canvas_value.height)
			primitives = canvas_value.primitives.map(
				|primitive| match primitive {
					Ellipse(shape) => { kind: 0, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0 }
					Line(shape) => { kind: 1, key: shape.key, label: shape.label, x: shape.x1, y: shape.y1, width: 0, height: 0, x2: shape.x2, y2: shape.y2, fill: color(Default), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0 }
					Rectangle(shape) => { kind: 2, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: shape.radius }
				},
			)
			id = Host.node_canvas!({ label: canvas_value.label, primitives, width_kind: width.kind, width: width.value, height_kind: height.kind, height: height.value, grow: canvas_value.grow, bg: color(canvas_value.bg), border_color: color(canvas_value.border_color), border_width: canvas_value.border_width, radius: canvas_value.radius })
			route = {
				id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, _| {
					event = Host.canvas_event!()
					phase = match event.phase {
						0 => Begin
						1 => Move
						2 => End
						_ => crash "invalid canvas pointer phase"
					}
					target = match event.target {
						0 => None
						value => Some(value)
					}
					(canvas_value.on_pointer)(current, { phase, x: event.x, y: event.y, target })
				},
			}
			{ root: id, routes: Index.set(routes, route.id, route), boundaries: record_route(boundaries, active_boundary, route.id) }
		}
		TextInput(input_value) => {
			style = style_args(input_value)
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
		Unknown => Work.next(|| done!(False))
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

	prepare_component! : Elem.BoundComponent(a), a, U64, Index(Route(a)), BuildingOwners(a), ([Retained(Building(a)), Descend(BoundaryInfo(a), Box(BuildingOwner))] -> Work) => Work
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
				{ key: resolved.instance, parent: Some(parent), path: parent_info.path.append(resolved.instance), render: bound.render, root: 0, bound: Some(bound), memo: Unknown, revision: 0, route_ids: RouteIds.empty, children: [] }
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
		prepared = { stored: boundaries, active: Box.box({ key: cleared.key, revision: cleared.revision, path: cleared.path, route_ids: RouteIds.empty, children: [] }) }
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
		root = if owner.key == 0 lowered.root else Host.node_boundary!(owner.key, lowered.root)
		Host.work_end!(3)
		Host.work_start!(0)
		completed = Box.unbox(lowered.boundaries.active)
		current = { ..cleared, route_ids: completed.route_ids, children: completed.children }
		var $live = Index.empty
		for child in current.children {
			$live = Index.set($live, child, True)
		}
		var $settled_routes = lowered.routes
		var $settled_boundaries = lowered.boundaries.stored
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
			offset = if levels >= source.path.len() 0 else source.path.len() - levels - 1
			owner = source.path.get(offset) ?? crash "missing delegated owner"
			target = Index.get(boundaries, owner) ?? crash "missing delegated component"
			var $dirty = boundaries
			for key in target.path {
				info = Index.get($dirty, key) ?? crash "missing update ancestor"
				if key != owner {
					$dirty = Index.set($dirty, key, { ..info, memo: Unknown })
					Host.component_work!(6, 1)
				}
			}
			match Action.inspect(action) {
				Update(next) => update_boundary!(next, None, owner, owner, render, routes, $dirty)
				Delegate(next) => update_boundary!(next, None, 0, 0, render, routes, $dirty)
				Task(task) => update_boundary!(task.pending, Some(task.run), owner, owner, render, routes, $dirty)
				_ => crash "action changed during dispatch"
			}
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
		unchanged!(
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

	start! : a, (a -> Elem(a)), { title : Str, width : U32, height : U32, background : Gui.Color, foreground : Gui.Color } => {}
	start! = |initial, render, window| {
		Host.window_config!(window.title, window.width, window.height, color(window.background), color(window.foreground))
		root = { key: 0, parent: None, path: [0], render: |state, done!| Work.next(|| done!(render(state))), root: 0, bound: None, memo: Unknown, revision: 0, route_ids: RouteIds.empty, children: [] }
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
