import Host
import Action exposing [Action]
import Elem exposing [Elem]
import Gui

Internal := [].{
	Route(a) : { boundary : U64, boundary_path : List(U64), id : U64, fire : (a -> Action(a)) }

	BoundaryInfo(a) : { key : U64, parent : [None, Some(U64)], path : List(U64), render : (a -> Elem(a)), root : U64 }

	Lowered(a) : {
		boundaries : List(BoundaryInfo(a)),
		next_boundary : U64,
		root : U64,
		routes : List(Route(a)),
	}

	lower_children! : List(Elem(a)), a, U64, U64, List(U64), List(Route(a)), List(BoundaryInfo(a)), U64 => {
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
		Row(children) => {
			builder = Host.children_begin!({})
			lowered = lower_children!(children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			id = Host.node_row!(builder)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Column(children) => {
			builder = Host.children_begin!({})
			lowered = lower_children!(children, state, next_boundary, active_boundary, boundary_path, routes, boundaries, builder)
			id = Host.node_column!(builder)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Button(button_value) => {
			label_elem = button_value.label.first() ?? crash "button label missing"
			label = lower!(label_elem, state, next_boundary, active_boundary, boundary_path, routes, boundaries)
			id = Host.node_button!(button_value.name, label.root)
			route = { id, boundary: active_boundary, boundary_path, fire: |current| (button_value.on_press)(current, {}) }
			{ root: id, next_boundary: label.next_boundary, routes: label.routes.append(route), boundaries: label.boundaries }
		}
		Checkbox(checkbox_value) => {
			max_style_value = 16384
			if checkbox_value.gap > max_style_value or checkbox_value.padding > max_style_value or checkbox_value.border_width > max_style_value or checkbox_value.radius > max_style_value or checkbox_value.font_size > max_style_value {
				crash "Gui style dimensions, spacing, borders, radii, and font sizes are at most 16384 logical pixels"
			}
			color = |value| match value {
				Default => 0x01000000
				Rgb(rgb) => if rgb <= 0x00ffffff { rgb } else { crash "Gui RGB colors are at most 0xffffff" }
			}
			length = |value| match value {
				Auto => { kind: 0, value: 0 }
				Fill => { kind: 1, value: 0 }
				Px(pixels) => if pixels <= max_style_value { { kind: 2, value: pixels } } else { crash "Gui pixel dimensions are at most 16384 logical pixels" }
			}
			overflow = |value| match value { Visible => 0, Clip => 1, Scroll => 2 }
			width = length(checkbox_value.width)
			height = length(checkbox_value.height)
			id = Host.node_checkbox!({
				label: checkbox_value.label,
				checked: checkbox_value.checked,
				enabled: checkbox_value.enabled,
				gap: checkbox_value.gap,
				padding: checkbox_value.padding,
				width_kind: width.kind,
				width: width.value,
				height_kind: height.kind,
				height: height.value,
				grow: checkbox_value.grow,
				bg: color(checkbox_value.bg),
				hover_bg: color(checkbox_value.hover_bg),
				active_bg: color(checkbox_value.active_bg),
				fg: color(checkbox_value.fg),
				border_color: color(checkbox_value.border_color),
				border_width: checkbox_value.border_width,
				radius: checkbox_value.radius,
				font_size: checkbox_value.font_size,
				overflow_x: overflow(checkbox_value.overflow_x),
				overflow_y: overflow(checkbox_value.overflow_y),
			})
			route = {
				id,
				boundary: active_boundary,
				boundary_path,
				fire: |current| if checkbox_value.enabled { (checkbox_value.on_change)(current, { checked: !checkbox_value.checked }) } else { Action.none },
			}
			{ root: id, next_boundary, routes: routes.append(route), boundaries }
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
				action = (route.fire)(state)
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

	start! : a, (a -> Elem(a)) => {}
	start! = |initial, render| {
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
