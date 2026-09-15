import Host
import Action exposing [Action]
import Elem exposing [Elem]

Internal := [].{
	Route(a) : { boundary : U64, boundary_path : List(U64), id : U64, on_press : (a, {} -> Action(a)) }

	BoundaryInfo(a) : { key : U64, parent : [None, Some(U64)], path : List(U64), render : (a -> Elem(a)), root : U64 }

	Lowered(a) : {
		boundaries : List(BoundaryInfo(a)),
		next_boundary : U64,
		root : U64,
		routes : List(Route(a)),
	}

	lower_children! : List(Elem(a)), a, U64, U64, List(U64), List(Route(a)), List(BoundaryInfo(a)) => {
		boundaries : List(BoundaryInfo(a)),
		ids : List(U64),
		next_boundary : U64,
		routes : List(Route(a)),
	}
	lower_children! = |children, state, next_boundary, active_boundary, boundary_path, routes, boundaries| {
		var $ids = []
		var $next = next_boundary
		var $routes = routes
		var $boundaries = boundaries
		for child in children {
			lowered = lower!(child, state, $next, active_boundary, boundary_path, $routes, $boundaries)
			$ids = $ids.append(lowered.root)
			$next = lowered.next_boundary
			$routes = lowered.routes
			$boundaries = lowered.boundaries
		}
		{ ids: $ids, next_boundary: $next, routes: $routes, boundaries: $boundaries }
	}

	lower! : Elem(a), a, U64, U64, List(U64), List(Route(a)), List(BoundaryInfo(a)) => Lowered(a)
	lower! = |elem, state, next_boundary, active_boundary, boundary_path, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = Host.node_text!(value)
			{ root: id, next_boundary, routes, boundaries }
		}
		Row(children) => {
			lowered = lower_children!(children, state, next_boundary, active_boundary, boundary_path, routes, boundaries)
			id = Host.node_row!(lowered.ids)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Column(children) => {
			lowered = lower_children!(children, state, next_boundary, active_boundary, boundary_path, routes, boundaries)
			id = Host.node_column!(lowered.ids)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Button(button_value) => {
			label_elem = button_value.label.first() ?? crash "button label missing"
			label = lower!(label_elem, state, next_boundary, active_boundary, boundary_path, routes, boundaries)
			id = Host.node_button!(button_value.name, label.root)
			route = { id, boundary: active_boundary, boundary_path, on_press: button_value.on_press }
			{ root: id, next_boundary: label.next_boundary, routes: label.routes.append(route), boundaries: label.boundaries }
		}
		Boundary(renderer) => {
			key = next_boundary
			child_path = boundary_path.append(key)
			child = lower!(renderer(state), state, key + 1, key, child_path, routes, boundaries)
			info = { key, parent: Some(active_boundary), path: child_path, render: renderer, root: child.root }
			{ ..child, boundaries: child.boundaries.append(info) }
		}
	}

	install! : a, (a -> Elem(a)), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	install! = |state, root_renderer, routes, boundaries, next_boundary| {
		dispatch! = |event_id| {
			Host.work_start!(0)
			route_result = routes.find_first(|route| route.id == event_id)
			Host.work_end!(0)
			match route_result {
				Ok(route) => {
					handler = route.on_press
					Host.work_start!(1)
					action = Action.inspect(handler(state, {}))
					Host.work_end!(1)
					match action {
						NoChange => {
							Host.apply!(NoChange)
							install!(state, root_renderer, routes, boundaries, next_boundary)
						}
						Update(next_state) => {
							Host.work_start!(0)
							boundary = boundaries.find_first(|entry| entry.key == route.boundary) ?? crash "missing render boundary"
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
							install!(next_state, root_renderer, lowered.routes, next_boundaries, lowered.next_boundary)
						}
					}
				}
				Err(_) => {
					Host.apply!(NoChange)
					install!(state, root_renderer, routes, boundaries, next_boundary)
				}
			}
		}
		Host.set_dispatch!(Box.box(dispatch!))
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
