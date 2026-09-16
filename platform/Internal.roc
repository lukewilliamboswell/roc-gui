import Host
import Action
import Elem
import Gui

Internal := [].{
	Route(a) : { boundary : U64, boundary_path : List(U64), id : U64, fire : (a, Str => Action(a)) }

	BoundaryInfo(a) : { key : U64, parent : [None, Some(U64)], path : List(U64), render : (a -> Elem(a)), root : U64 }

	Lowered(a) : {
		boundaries : List(BoundaryInfo(a)),
		next_boundary : U64,
		root : U64,
		routes : List(Route(a)),
	}

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
	U64,
	List(U64),
	List(Route(a)),
	List(BoundaryInfo(a)),
	U64 => {
		boundaries : List(BoundaryInfo(a)),
		next_boundary : U64,
		routes : List(Route(a)),
	}
	lower_children! = |children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder| {
		var $next = next_boundary
		var $routes = routes
		var $boundaries = boundaries
		for child in children {
			lowered = lower!(child, state, $next, active_boundary, boundary_path, $routes, $boundaries)
			Host.children_push!(builder, lowered.root)
			$next = lowered.next_boundary
			$routes = lowered.routes
			$boundaries = lowered.boundaries
		}
		{ next_boundary: $next, routes: $routes, boundaries: $boundaries }
	}

	lower! : Elem(a), a, U64, U64, List(U64), List(Route(a)), List(BoundaryInfo(a)) => Lowered(a)
	lower! = |elem, state, next_boundary, active_boundary, boundary_path, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = Host.node_text!(value)
			{ root: id, next_boundary, routes, boundaries }
		}
		Row(value) => {
			builder = Host.children_begin!()
			lowered = lower_children!(value.children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			style = style_args(value.props)
			id = Host.node_row!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Column(value) => {
			builder = Host.children_begin!()
			lowered = lower_children!(value.children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			style = style_args(value.props)
			id = Host.node_column!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Dialog(value) => {
			builder = Host.children_begin!()
			lowered = lower_children!(value.children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			style = style_args(value.props)
			id = Host.node_dialog!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = { id, boundary: active_boundary, boundary_path, fire: |current, _| (value.props.on_dismiss)(current, {}) }
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes.append(route), boundaries: lowered.boundaries }
		}
		Panel(value) => {
			builder = Host.children_begin!()
			lowered = lower_children!(value.children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			style = style_args(value.props)
			id = Host.node_panel!({ builder, label: value.props.label, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Scroll(scroll_value) => {
			child = lower!(scroll_value.content, state, next_boundary, active_boundary, boundary_path, routes, boundaries)
			axis = match scroll_value.axis {
				Vertical => 0
				Horizontal => 1
				Both => 2
			}
			id = Host.node_scroll!({ axis, child: child.root, name: scroll_value.name })
			{ root: id, next_boundary: child.next_boundary, routes: child.routes, boundaries: child.boundaries }
		}
		VirtualList(list_value) => {
			builder = Host.children_begin!()
			var $next = next_boundary
			var $routes = routes
			var $boundaries = boundaries
			for item in list_value.items {
				lowered = lower!(item.content, state, $next, active_boundary, boundary_path, $routes, $boundaries)
				row = Host.node_virtual_item!(item.key, lowered.root)
				Host.children_push!(builder, row)
				$next = lowered.next_boundary
				$routes = lowered.routes
				$boundaries = lowered.boundaries
			}
			id = Host.node_virtual_list!({ builder, name: list_value.name, row_height: list_value.row_height })
			{ root: id, next_boundary: $next, routes: $routes, boundaries: $boundaries }
		}
		ActionButton(button_value) => {
			style = style_args(button_value)
			id = Host.node_action_button!({ caption: button_value.caption, label: button_value.label, enabled: button_value.enabled, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = {
				id,
				boundary: active_boundary,
				boundary_path,
				fire: |current, _| if button_value.enabled {
					(button_value.on_press)(current, {})
				} else {
					Action.none
				},
			}
			{ root: id, next_boundary, routes: routes.append(route), boundaries }
		}
		Checkbox(checkbox_value) => {
			style = style_args(checkbox_value)
			id = Host.node_checkbox!({
				label: checkbox_value.label,
				checked: checkbox_value.checked,
				enabled: checkbox_value.enabled,
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
				text_overflow: style.text_overflow,
				overflow_x: style.overflow_x,
				overflow_y: style.overflow_y,
				align: style.align,
				justify: style.justify,
			})
			route = {
				id,
				boundary: active_boundary,
				boundary_path,
				fire: |current, _| if checkbox_value.enabled {
					(checkbox_value.on_change)(current, { checked: !checkbox_value.checked })
				} else {
					Action.none
				},
			}
			{ root: id, next_boundary, routes: routes.append(route), boundaries }
		}
		Textarea(textarea_value) => {
			style = style_args(textarea_value)
			id = Host.node_textarea!({ label: textarea_value.label, value: textarea_value.value, placeholder: textarea_value.placeholder, enabled: textarea_value.enabled, read_only: textarea_value.read_only, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			route = {
				id,
				boundary: active_boundary,
				boundary_path,
				fire: |current, input| if textarea_value.enabled and !textarea_value.read_only {
					(textarea_value.on_input)(current, { value: input })
				} else {
					Action.none
				},
			}
			{ root: id, next_boundary, routes: routes.append(route), boundaries }
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
			id = Host.node_image!({ label: image_value.label, bytes: image_value.bytes, format, fit, grayscale: image_value.grayscale, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			{ root: id, next_boundary, routes, boundaries }
		}
		Canvas(canvas_value) => {
			width = length(canvas_value.width)
			height = length(canvas_value.height)
			primitives = canvas_value.primitives.map(|primitive| match primitive {
				Ellipse(shape) => { kind: 0, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0 }
				Line(shape) => { kind: 1, key: shape.key, label: shape.label, x: shape.x1, y: shape.y1, width: 0, height: 0, x2: shape.x2, y2: shape.y2, fill: color(Default), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: 0 }
				Rectangle(shape) => { kind: 2, key: shape.key, label: shape.label, x: shape.x, y: shape.y, width: shape.width, height: shape.height, x2: 0, y2: 0, fill: color(shape.fill), stroke: color(shape.stroke), stroke_width: shape.stroke_width, radius: shape.radius }
			})
			id = Host.node_canvas!({ label: canvas_value.label, primitives, width_kind: width.kind, width: width.value, height_kind: height.kind, height: height.value, grow: canvas_value.grow, bg: color(canvas_value.bg), border_color: color(canvas_value.border_color), border_width: canvas_value.border_width, radius: canvas_value.radius })
			route = { id, boundary: active_boundary, boundary_path, fire: |current, _| {
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
			} }
			{ root: id, next_boundary, routes: routes.append(route), boundaries }
		}
		TextInput(input_value) => {
			style = style_args(input_value)
			ids = Host.node_text_input!({ label: input_value.label, value: input_value.value, placeholder: input_value.placeholder, enabled: input_value.enabled, gap: style.gap, padding_top: style.padding_top, padding_right: style.padding_right, padding_bottom: style.padding_bottom, padding_left: style.padding_left, width_kind: style.width_kind, width: style.width, height_kind: style.height_kind, height: style.height, min_width_kind: style.min_width_kind, min_width: style.min_width, min_height_kind: style.min_height_kind, min_height: style.min_height, max_width_kind: style.max_width_kind, max_width: style.max_width, max_height_kind: style.max_height_kind, max_height: style.max_height, grow: style.grow, bg: style.bg, hover_bg: style.hover_bg, active_bg: style.active_bg, disabled_bg: style.disabled_bg, disabled_fg: style.disabled_fg, focus_color: style.focus_color, fg: style.fg, border_color: style.border_color, border_top: style.border_top, border_right: style.border_right, border_bottom: style.border_bottom, border_left: style.border_left, radius: style.radius, font_size: style.font_size, font_weight: style.font_weight, text_overflow: style.text_overflow, overflow_x: style.overflow_x, overflow_y: style.overflow_y, align: style.align, justify: style.justify })
			change_route : Route(a)
			change_route = {
				id: ids.change,
				boundary: active_boundary,
				boundary_path,
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
				boundary_path,
				fire: |current, input| if input_value.enabled {
					(input_value.on_submit)(current, { value: input })
				} else {
					Action.none
				},
			}
			{ root: ids.id, next_boundary, routes: routes.append(change_route).append(submit_route), boundaries }
		}
		Boundary(renderer) => {
			key = next_boundary
			child_path = boundary_path.append(key)
			child = lower!(renderer(state), state, key + 1, key, child_path, routes, boundaries)
			info = { key, parent: Some(active_boundary), path: child_path, render: renderer, root: child.root }
			{ ..child, boundaries: child.boundaries.append(info) }
		}
	}

	apply_action! : Action(a), a, U64, (a -> Elem(a)), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	apply_action! = |action_value, state, boundary_key, root_renderer, routes, boundaries, next_boundary| match Action.inspect(action_value) {
		NoChange => {
			Host.apply!(NoChange)
			install!(state, root_renderer, routes, boundaries, next_boundary)
		}
		Update(next_state) => update_boundary!(next_state, None, boundary_key, root_renderer, routes, boundaries, next_boundary)
		Task(task_value) => update_boundary!(task_value.pending, Some(task_value.run), boundary_key, root_renderer, routes, boundaries, next_boundary)
	}

	update_boundary! : a, [None, Some(Box((() => Box((Box(a) -> Box(Action(a)))))))], U64, (a -> Elem(a)), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	update_boundary! = |next_state, task, boundary_key, root_renderer, routes, boundaries, next_boundary| {
		Host.work_start!(0)
		boundary = boundaries.find_first(|entry| entry.key == boundary_key) ?? crash "missing render boundary"
		renderer = boundary.render
		kept_routes = routes.keep_if(|entry| !entry.boundary_path.contains(boundary.key))
		kept_boundaries = boundaries.keep_if(|entry| !entry.path.contains(boundary.key))
		Host.work_end!(0)
		Host.work_start!(2)
		rendered = renderer(next_state)
		Host.work_end!(2)
		Host.work_start!(3)
		lowered = lower!(rendered, next_state, next_boundary, boundary.key, boundary.path, kept_routes, kept_boundaries)
		Host.work_end!(3)
		next_boundary_info = { ..boundary, root: lowered.root }
		next_boundaries = lowered.boundaries.append(next_boundary_info)
		Host.apply!(Replace({ old_root: boundary.root, root: lowered.root }))
		match task {
			Some(worker) => Host.enqueue_task!(worker)
			None => {}
		}
		install!(next_state, root_renderer, lowered.routes, next_boundaries, lowered.next_boundary)
	}

	install! : a, (a -> Elem(a)), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	install! = |state, root_renderer, routes, boundaries, next_boundary| {
		dispatch! = |event_id| {
			Host.work_start!(0)
			route_result = routes.find_first(|route| route.id == event_id)
			Host.work_end!(0)
			match route_result {
				Ok(route) => {
					Host.work_start!(1)
					input = Host.input_value!()
					action = (route.fire)(state, input)
					Host.work_end!(1)
					apply_action!(action, state, route.boundary, root_renderer, routes, boundaries, next_boundary)
				}
				Err(_) => {
					Host.apply!(NoChange)
					install!(state, root_renderer, routes, boundaries, next_boundary)
				}
			}
		}
		complete! = |completion_box| {
			completion = Box.unbox(completion_box)
			Host.work_start!(1)
			action = Box.unbox(completion(Box.box(state)))
			Host.work_end!(1)
			apply_action!(action, state, 0, root_renderer, routes, boundaries, next_boundary)
		}
		Host.set_dispatch!(Box.box(dispatch!))
		Host.set_task_dispatch!(Box.box(complete!))
	}

	start! : a, (a -> Elem(a)), { title : Str, width : U32, height : U32, background : Gui.Color, foreground : Gui.Color } => {}
	start! = |initial, render, window| {
		Host.window_config!(window.title, window.width, window.height, color(window.background), color(window.foreground))
		root_renderer = render
		Host.work_start!(2)
		rendered = render(initial)
		Host.work_end!(2)
		Host.work_start!(3)
		lowered = lower!(rendered, initial, 1, 0, [0], [], [])
		Host.work_end!(3)
		root_boundary = { key: 0, parent: None, path: [0], render: root_renderer, root: lowered.root }
		Host.apply!(Mount({ root: lowered.root }))
		install!(initial, root_renderer, lowered.routes, lowered.boundaries.append(root_boundary), lowered.next_boundary)
	}
}
