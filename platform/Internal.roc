import Host
import Action
import Elem
import Gui
import Session
import Index

Internal := [].{
	Route(a) : { boundary : U64, id : U64, revision : U64, fire : (a, Str => Action(a)) }

	BoundaryInfo(a) : {
		key : U64,
		parent : [None, Some(U64)],
		path : List(U64),
		render : a -> Elem(a),
		root : U64,
		bound : [None, Some(Elem.BoundComponent(a))],
		memo : [Unknown, Known(Box(a -> Bool))],
		revision : U64,
		route_ids : List(U64),
		children : List(U64),
	}

	Lowered(a) : {
		boundaries : Index(BoundaryInfo(a)),
		root : U64,
		routes : Index(Route(a)),
	}

	BuildingOwner : { key : U64, revision : U64, path : List(U64), route_ids : List(U64), children : List(U64) }

	# Keep the active metadata boxed across recursive lowering. With the 09-12
	# compiler, passing even this slim record by value overflows the normal stack
	# in deep-1k. Revisit when unboxed lowering passes that spec at the normal limit.
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

	lower_children! : List(Elem(a)),
	a,
	U64,
	Index(Route(a)),
	BuildingOwners(a),
	U64 => {
		boundaries : BuildingOwners(a),
		routes : Index(Route(a)),
	}
	lower_children! = |children, state, active_boundary, routes, boundaries, builder| {
		var $routes = routes
		var $boundaries = boundaries
		var $position = 0.U64
		for child in children {
			lowered = lower!(child, state, active_boundary, $routes, $boundaries, $position)
			$position = $position + 1
			Host.children_push!(builder, lowered.root)
			$routes = lowered.routes
			$boundaries = lowered.boundaries
		}
		{ routes: $routes, boundaries: $boundaries }
	}

	lower! : Elem(a), a, U64, Index(Route(a)), BuildingOwners(a), U64 => Building(a)
	lower! = |elem, state, active_boundary, routes, boundaries, position| {
		scope = match Elem.inspect(elem) {
			Row(value) => Some({ tag: 1.U8, label: value.props.label })
			Column(value) => Some({ tag: 2.U8, label: value.props.label })
			Panel(value) => Some({ tag: 3.U8, label: value.props.label })
			Dialog(value) => Some({ tag: 4.U8, label: value.props.label })
			Scroll(value) => Some({ tag: 5.U8, label: value.label })
			VirtualList(value) => Some({ tag: 6.U8, label: value.label })
			_ => None
		}
		match scope {
			Some(segment) => Host.scope_enter!(segment.tag, segment.label, position)
			None => {}
		}
		lowered_node = match Elem.inspect(elem) {
			Row(value) => {
				builder = Host.children_begin!()
				lowered = lower_children!(value.children, state, active_boundary, routes, boundaries, builder)
				style = style_args(value.props)
				id = Host.node_row!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
				{ root: id, routes: lowered.routes, boundaries: lowered.boundaries }
			}
			Column(value) => {
				builder = Host.children_begin!()
				lowered = lower_children!(value.children, state, active_boundary, routes, boundaries, builder)
				style = style_args(value.props)
				id = Host.node_column!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
				{ root: id, routes: lowered.routes, boundaries: lowered.boundaries }
			}
			Dialog(value) => {
				builder = Host.children_begin!()
				lowered = lower_children!(value.children, state, active_boundary, routes, boundaries, builder)
				style = style_args(value.props)
				id = Host.node_dialog!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
				route = { id, boundary: active_boundary, revision: (Box.unbox(lowered.boundaries.active)).revision, fire: |current, _| (value.props.on_dismiss)(current, {}) }
				{ root: id, routes: Index.set(lowered.routes, route.id, route), boundaries: record_route(lowered.boundaries, active_boundary, route.id) }
			}
			Panel(value) => {
				builder = Host.children_begin!()
				# The heading is the panel's own, so the platform paints it rather
				# than each application opening its surface with a caption element.
				if value.props.heading != "" {
					if value.props.heading_size > max_style_value {
						crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
					}
					if value.props.heading_weight != 0 and (value.props.heading_weight < 100 or value.props.heading_weight > 900) {
						crash "Gui font_weight is 0 for the native default, or 100 through 900"
					}
					heading = Host.node_styled_text!({ value: value.props.heading, fg: color(value.props.heading_color), font_size: value.props.heading_size, font_weight: value.props.heading_weight, font_face: 0 })
					Host.children_push!(builder, heading)
				} else {
					{}
				}
				lowered = lower_children!(value.children, state, active_boundary, routes, boundaries, builder)
				style = style_args(value.props)
				id = Host.node_panel!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
				{ root: id, routes: lowered.routes, boundaries: lowered.boundaries }
			}
			Scroll(scroll_value) => {
				child = lower!(scroll_value.content, state, active_boundary, routes, boundaries, 0)
				axis = match scroll_value.axis {
					Vertical => 0
					Horizontal => 1
					Both => 2
				}
				style = style_args(scroll_value)
				id = Host.node_scroll!({
					axis,
					child: child.root,
					name: scroll_value.label,
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
				{ root: id, routes: child.routes, boundaries: child.boundaries }
			}
			VirtualList(list_value) => {
				builder = Host.children_begin!()
				var $routes = routes
				var $boundaries = boundaries
				for item in list_value.items {
					Host.scope_enter!(7, item.key.to_str(), 0)
					lowered = lower!(item.content, state, active_boundary, $routes, $boundaries, 0)
					row = Host.node_virtual_item!(item.key, lowered.root)
					Host.scope_exit!()
					Host.children_push!(builder, row)
					$routes = lowered.routes
					$boundaries = lowered.boundaries
				}
				style = style_args(list_value)
				id = Host.node_virtual_list!({
					builder,
					name: list_value.label,
					row_height: list_value.row_height,
					row_gap: list_value.row_gap,
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
				{ root: id, routes: $routes, boundaries: $boundaries }
			}
			Component(bound) => mount_component!(bound, state, active_boundary, routes, boundaries)
			_ => lower_leaf!(elem, active_boundary, routes, boundaries)
		}
		match scope {
			Some(_) => Host.scope_exit!()
			None => {}
		}
		lowered_node
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
			id = Host.node_action_button!({ caption: button_value.caption, label: button_value.label, enabled: button_value.enabled, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, shadow: style.shadow, shadow_y: style.shadow_y, shadow_color: style.shadow_color, shadow_alpha: style.shadow_alpha, font_face: style.font_face, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = {
				id,
				boundary: active_boundary,
				revision: (Box.unbox(boundaries.active)).revision,
				fire: |current, _| if button_value.enabled {
					(button_value.on_press)(current, {})
				} else {
					Action.none
				},
			}
			{ root: id, routes: Index.set(routes, route.id, route), boundaries: record_route(boundaries, active_boundary, route.id) }
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
		{ stored: boundaries.stored, active: Box.box({ ..owner, route_ids: owner.route_ids.append(id) }) }
	}

	unchanged! : BoundaryInfo(a), a => Bool
	unchanged! = |owner, state| match owner.memo {
		Unknown => False
		Known(boxed) => {
			Host.work_start!(4)
			Host.component_work!(1, 1)
			result = Box.unbox(boxed)(state)
			Host.work_end!(4)
			if result {
				Host.component_work!(2, 1)
			}
			result
		}
	}

	mount_component! : Elem.BoundComponent(a), a, U64, Index(Route(a)), BuildingOwners(a) => Building(a)
	mount_component! = |bound, state, parent, routes, boundaries| {
		Host.work_end!(3)
		Host.work_start!(0)
		resolved = match Elem.Key.inspect(bound.key) {
			Name(name) => Host.component_resolve!(bound.definition, 1, name, 0)
			Id(id) => Host.component_resolve!(bound.definition, 0, "", id)
		}
		Host.component_work!(5, 1)
		prior = Index.get(boundaries.stored, resolved.instance)
		parent_info = Box.unbox(boundaries.active)
		if parent_info.key != parent {
			crash "mismatched component parent"
		}
		owner = match prior {
			Ok(previous) => { ..previous, bound: Some(bound), render: bound.render }
			Err(_) => {
				Host.component_work!(3, 1)
				{ key: resolved.instance, parent: Some(parent), path: parent_info.path.append(resolved.instance), render: bound.render, root: 0, bound: Some(bound), memo: Unknown, revision: 0, route_ids: [], children: [] }
			}
		}
		with_parent = Box.box({ ..parent_info, children: parent_info.children.append(resolved.instance) })
		if !(bound.exists)(state) {
			crash "render emitted a removed component"
		}
		Host.work_end!(0)
		if unchanged!(owner, state) {
			Host.work_start!(3)
			root = Host.retain_subtree!(owner.root)
			{ root, routes, boundaries: { stored: Index.set(boundaries.stored, owner.key, owner), active: with_parent } }
		} else {
			Host.component_enter!(owner.key)
			rebuilt = rebuild!(owner, state, routes, boundaries.stored)
			Host.component_exit!()
			Host.work_start!(3)
			{ root: rebuilt.root, routes: rebuilt.routes, boundaries: { stored: rebuilt.boundaries, active: with_parent } }
		}
	}

	retire! : U64, Index(Route(a)), Index(BoundaryInfo(a)) => { routes : Index(Route(a)), boundaries : Index(BoundaryInfo(a)) }
	retire! = |key, routes, boundaries| {
		owner = Index.get(boundaries, key) ?? crash "missing retired component"
		var $routes = routes
		var $boundaries = boundaries
		for child in owner.children {
			retired = retire!(child, $routes, $boundaries)
			$routes = retired.routes
			$boundaries = retired.boundaries
		}
		for id in owner.route_ids {
			$routes = Index.remove($routes, id)
		}
		Host.component_work!(4, 1)
		{ routes: $routes, boundaries: Index.remove($boundaries, key) }
	}

	rebuild! : BoundaryInfo(a), a, Index(Route(a)), Index(BoundaryInfo(a)) => Lowered(a)
	rebuild! = |owner, state, routes, boundaries| {
		Host.work_start!(0)
		var $routes = routes
		for id in owner.route_ids {
			$routes = Index.remove($routes, id)
		}
		cleared = { ..owner, revision: owner.revision + 1, route_ids: [], children: [], memo: Unknown }
		# Keep growing metadata out of the persistent index until this owner is
		# complete; per-route publication shares and repeatedly copies its lists.
		prepared = { stored: boundaries, active: Box.box({ key: cleared.key, revision: cleared.revision, path: cleared.path, route_ids: [], children: [] }) }
		Host.work_end!(0)
		Host.work_start!(2)
		Host.component_work!(0, 1)
		rendered = (owner.render)(state)
		Host.work_end!(2)
		Host.work_start!(3)
		lowered = lower!(rendered, state, owner.key, $routes, prepared, 0)
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
		memo = match owner.bound {
			None => Unknown
			Some(bound) => match bound.remember {
				None => Unknown
				Some(capture) => Known(capture(state))
			}
		}
		updated = { ..current, root, memo }
		Host.work_end!(0)
		{ root, routes: $settled_routes, boundaries: Index.set($settled_boundaries, owner.key, updated) }
	}

	exists : Index(BoundaryInfo(a)), U64, a -> Bool
	exists = |boundaries, key, state| match Index.get(boundaries, key) {
		Err(_) => False
		Ok(owner) => {
			var $exists = True
			for ancestor in owner.path {
				if $exists {
					info = Index.get(boundaries, ancestor) ?? crash "missing component ancestor"
					$exists = match info.bound {
						None => True
						Some(bound) => (bound.exists)(state)
					}
				}
			}
			$exists
		}
	}

	apply_action! : Action(a), a, U64, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => {}
	apply_action! = |action, state, origin, render, routes, boundaries| {
		match Action.inspect(action) {
			NoChange => {
				Host.apply!(NoChange)
				install!(state, render, routes, boundaries)
			}
			_ => {
				source = Index.get(boundaries, origin) ?? crash "missing action owner"
				levels = Action.owner_levels(action)
				offset = if levels >= source.path.len() 0 else source.path.len() - levels - 1
				owner = source.path.get(offset) ?? crash "missing delegated owner"
				target = Index.get(boundaries, owner) ?? crash "missing delegated component"
				var $render_owner = owner
				var $render_depth = offset
				var $dirty = boundaries
				var $depth = 0.U64
				for key in target.path {
					info = Index.get($dirty, key) ?? crash "missing update ancestor"
					if key != owner {
						$dirty = Index.set($dirty, key, { ..info, memo: Unknown })
						Host.component_work!(6, 1)
					}
					match info.bound {
						Some(bound) => if bound.update_scope == Parent and $depth > 0 and $depth - 1 < $render_depth {
							$render_depth = $depth - 1
							$render_owner = target.path.get($render_depth) ?? crash "missing render ancestor"
						}
						None => {}
					}
					$depth = $depth + 1
				}
				match Action.inspect(action) {
					Update(next) => update_boundary!(next, None, owner, $render_owner, render, routes, $dirty)
					Delegate(next) => update_boundary!(next, None, 0, 0, render, routes, $dirty)
					Task(task) => update_boundary!(task.pending, Some(task.run), owner, $render_owner, render, routes, $dirty)
					NoChange => crash "action changed during dispatch"
				}
			}
		}
	}

	update_boundary! : a, [None, Some(Box((() => Box((Box(a) -> Box(Action(a)))))))], U64, U64, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => {}
	update_boundary! = |state, task, task_owner, render_owner, render, routes, boundaries| {
		owner = Index.get(boundaries, render_owner) ?? crash "missing render owner"
		if unchanged!(owner, state) {
			Host.apply!(NoChange)
			match task {
				None => {}
				Some(worker) => Host.enqueue_task!(task_owner, worker)
			}
			install!(state, render, routes, boundaries)
		} else {
			Host.begin_render!(render_owner)
			lowered = rebuild!(owner, state, routes, boundaries)
			Host.apply!(Replace({ old_root: owner.root, root: lowered.root }))
			match task {
				None => {}
				Some(worker) => Host.enqueue_task!(task_owner, worker)
			}
			install!(state, render, lowered.routes, lowered.boundaries)
		}
	}

	install! : a, (a -> Elem(a)), Index(Route(a)), Index(BoundaryInfo(a)) => {}
	install! = |state, render, routes, boundaries| {
		dispatch! = |input| match Session.inspect(input) {
			Event(id) => {
				Host.work_start!(0)
				Host.component_work!(5, 1)
				found = Index.get(routes, id)
				Host.work_end!(0)
				match found {
					Ok(route) => if exists(boundaries, route.boundary, state) and route.revision == revision(boundaries, route.boundary) {
						Host.work_start!(1)
						action = (route.fire)(state, Host.input_value!())
						Host.work_end!(1)
						apply_action!(action, state, route.boundary, render, routes, boundaries)
					} else {
						Host.apply!(NoChange)
						install!(state, render, routes, boundaries)
					}
					Err(_) => {
						Host.apply!(NoChange)
						install!(state, render, routes, boundaries)
					}
				}
			}
			Completion(completed) => {
				if exists(boundaries, completed.owner, state) {
					Host.work_start!(1)
					action = Box.unbox(Box.unbox(completed.resume)(Box.box(state)))
					Host.work_end!(1)
					apply_action!(action, state, completed.owner, render, routes, boundaries)
				} else {
					Host.apply!(NoChange)
					install!(state, render, routes, boundaries)
				}
			}
		}
		Host.set_dispatch!(Box.box(dispatch!))
	}

	start! : a, (a -> Elem(a)), { title : Str, width : U32, height : U32, background : Gui.Color, foreground : Gui.Color } => {}
	start! = |initial, render, window| {
		Host.window_config!(window.title, window.width, window.height, color(window.background), color(window.foreground))
		root = { key: 0, parent: None, path: [0], render, root: 0, bound: None, memo: Unknown, revision: 0, route_ids: [], children: [] }
		Host.begin_render!(0)
		lowered = rebuild!(root, initial, Index.empty, Index.empty)
		Host.apply!(Mount({ root: lowered.root }))
		install!(initial, render, lowered.routes, lowered.boundaries)
	}
}
