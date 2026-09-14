import Host
import Action exposing [Action]
import Elem exposing [Elem]

Internal := [].{
	Route(a) : { boundary : U64, id : U64, on_press : (a, {} -> Action(a)) }

	BoundaryInfo(a) : { key : U64, parent : [None, Some(U64)], render : (a -> Elem(a)), root : U64 }

	Lowered(a) : {
		boundaries : List(BoundaryInfo(a)),
		next_boundary : U64,
		root : U64,
		routes : List(Route(a)),
	}

	lower_children! : List(Elem(a)), a, U64, U64, [None, Some(U64)], List(Route(a)), List(BoundaryInfo(a)) => {
		boundaries : List(BoundaryInfo(a)),
		ids : List(U64),
		next_boundary : U64,
		routes : List(Route(a)),
	}
	lower_children! = |children, state, next_boundary, active_boundary, parent_boundary, routes, boundaries| {
		var $ids = []
		var $next = next_boundary
		var $routes = routes
		var $boundaries = boundaries
		for child in children {
			lowered = lower!(child, state, $next, active_boundary, parent_boundary, $routes, $boundaries)
			$ids = $ids.append(lowered.root)
			$next = lowered.next_boundary
			$routes = lowered.routes
			$boundaries = lowered.boundaries
		}
		{ ids: $ids, next_boundary: $next, routes: $routes, boundaries: $boundaries }
	}

	lower! : Elem(a), a, U64, U64, [None, Some(U64)], List(Route(a)), List(BoundaryInfo(a)) => Lowered(a)
	lower! = |elem, state, next_boundary, active_boundary, parent_boundary, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = Host.node_text!(value)
			{ root: id, next_boundary, routes, boundaries }
		}
		Row(children) => {
			lowered = lower_children!(children, state, next_boundary, active_boundary, parent_boundary, routes, boundaries)
			id = Host.node_row!(lowered.ids)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Column(children) => {
			lowered = lower_children!(children, state, next_boundary, active_boundary, parent_boundary, routes, boundaries)
			id = Host.node_column!(lowered.ids)
			{ root: id, next_boundary: lowered.next_boundary, routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Button(button_value) => {
			label_elem = button_value.label.first() ?? crash "button label missing"
			label = lower!(label_elem, state, next_boundary, active_boundary, parent_boundary, routes, boundaries)
			id = Host.node_button!(button_value.name, label.root)
			route = { id, boundary: active_boundary, on_press: button_value.on_press }
			{ root: id, next_boundary: label.next_boundary, routes: label.routes.append(route), boundaries: label.boundaries }
		}
		Boundary(renderer) => {
			key = next_boundary
			child = lower!(renderer(state), state, key + 1, key, Some(active_boundary), routes, boundaries)
			info = { key, parent: Some(active_boundary), render: renderer, root: child.root }
			{ ..child, boundaries: child.boundaries.append(info) }
		}
	}

	is_descendant : U64, U64, List(BoundaryInfo(a)) -> Bool
	is_descendant = |candidate, ancestor, boundaries| {
		if candidate == ancestor {
			True
		} else {
			match boundaries.find_first(|entry| entry.key == candidate) {
				Ok(entry) => match entry.parent {
					Some(parent) => is_descendant(parent, ancestor, boundaries)
					None => False
				}
				Err(_) => False
			}
		}
	}

	install! : a, (a -> Elem(a)), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	install! = |state, root_renderer, routes, boundaries, next_boundary| {
		dispatch! = |event_id| {
			match routes.find_first(|route| route.id == event_id) {
				Ok(route) => {
					handler = route.on_press
					match Action.inspect(handler(state, {})) {
						NoChange => {
							Host.apply!(NoChange)
							install!(state, root_renderer, routes, boundaries, next_boundary)
						}
						Update(next_state) => {
							boundary = boundaries.find_first(|entry| entry.key == route.boundary) ?? crash "missing render boundary"
							renderer = boundary.render
							kept_routes = routes.keep_if(|entry| !is_descendant(entry.boundary, boundary.key, boundaries))
							kept_boundaries = boundaries.keep_if(|entry| !is_descendant(entry.key, boundary.key, boundaries))
							lowered = lower!(renderer(next_state), next_state, next_boundary, boundary.key, boundary.parent, kept_routes, kept_boundaries)
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
		lowered = lower!(render(initial), initial, 1, 0, None, [], [])
		root_boundary = { key: 0, parent: None, render: root_renderer, root: lowered.root }
		Host.apply!(Mount({ root: lowered.root }))
		install!(initial, root_renderer, lowered.routes, lowered.boundaries.append(root_boundary), lowered.next_boundary)
	}
}
