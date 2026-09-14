import Host
import Action exposing [Action]
import Elem exposing [Elem]

Internal := [].{
	Route(a) : { boundary : U64, id : U64, on_press : Box((a, {} -> Action(a))) }

	BoundaryInfo(a) : { key : U64, parent : [None, Some(U64)], render : Box((a -> Elem(a))), root : U64 }

	Lowered(a) : {
		boundaries : List(BoundaryInfo(a)),
		next_id : U64,
		nodes : List(Host.NativeNode),
		root : U64,
		routes : List(Route(a)),
	}

	lower_children : List(Elem(a)), a, U64, U64, [None, Some(U64)], List(Host.NativeNode), List(Route(a)), List(BoundaryInfo(a)) -> {
		boundaries : List(BoundaryInfo(a)),
		ids : List(U64),
		next_id : U64,
		nodes : List(Host.NativeNode),
		routes : List(Route(a)),
	}
	lower_children = |children, state, next_id, active_boundary, parent_boundary, nodes, routes, boundaries| {
		var $ids = []
		var $next = next_id
		var $nodes = nodes
		var $routes = routes
		var $boundaries = boundaries
		for child in children {
			lowered = lower(child, state, $next, active_boundary, parent_boundary, $nodes, $routes, $boundaries)
			$ids = $ids.append(lowered.root)
			$next = lowered.next_id
			$nodes = lowered.nodes
			$routes = lowered.routes
			$boundaries = lowered.boundaries
		}
		{ ids: $ids, next_id: $next, nodes: $nodes, routes: $routes, boundaries: $boundaries }
	}

	lower : Elem(a), a, U64, U64, [None, Some(U64)], List(Host.NativeNode), List(Route(a)), List(BoundaryInfo(a)) -> Lowered(a)
	lower = |elem, state, next_id, active_boundary, parent_boundary, nodes, routes, boundaries| match Elem.inspect(elem) {
		Text(value) => {
			id = next_id
			{ root: id, next_id: id + 1, nodes: nodes.append({ id, kind: Text(value), children: [] }), routes, boundaries }
		}
		Row(children) => {
			id = next_id
			lowered = lower_children(children, state, id + 1, active_boundary, parent_boundary, nodes, routes, boundaries)
			{ root: id, next_id: lowered.next_id, nodes: lowered.nodes.append({ id, kind: Row, children: lowered.ids }), routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Column(children) => {
			id = next_id
			lowered = lower_children(children, state, id + 1, active_boundary, parent_boundary, nodes, routes, boundaries)
			{ root: id, next_id: lowered.next_id, nodes: lowered.nodes.append({ id, kind: Column, children: lowered.ids }), routes: lowered.routes, boundaries: lowered.boundaries }
		}
		Button(button_value) => {
			id = next_id
			label = lower(Box.unbox(button_value.label), state, id + 1, active_boundary, parent_boundary, nodes, routes, boundaries)
			route = { id, boundary: active_boundary, on_press: button_value.on_press }
			{ root: id, next_id: label.next_id, nodes: label.nodes.append({ id, kind: Button, children: [label.root] }), routes: label.routes.append(route), boundaries: label.boundaries }
		}
		Boundary(renderer_box) => {
			key = next_id
			renderer = Box.unbox(renderer_box)
			child = lower(renderer(state), state, key + 1, key, Some(active_boundary), nodes, routes, boundaries)
			info = { key, parent: Some(active_boundary), render: renderer_box, root: child.root }
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

	install! : a, Box((a -> Elem(a))), List(Route(a)), List(BoundaryInfo(a)), U64 => {}
	install! = |state, root_renderer, routes, boundaries, next_id| {
		dispatch! = |event_id| {
			match routes.find_first(|route| route.id == event_id) {
				Ok(route) => {
					handler = Box.unbox(route.on_press)
					match Action.inspect(handler(state, {})) {
						NoChange => {
							Host.apply!(NoChange)
							install!(state, root_renderer, routes, boundaries, next_id)
						}
						Update(next_state) => {
							boundary = boundaries.find_first(|entry| entry.key == route.boundary) ?? crash "missing render boundary"
							renderer = Box.unbox(boundary.render)
							kept_routes = routes.keep_if(|entry| !is_descendant(entry.boundary, boundary.key, boundaries))
							kept_boundaries = boundaries.keep_if(|entry| !is_descendant(entry.key, boundary.key, boundaries))
							lowered = lower(renderer(next_state), next_state, next_id, boundary.key, boundary.parent, [], kept_routes, kept_boundaries)
							next_boundary = { ..boundary, root: lowered.root }
							next_boundaries = lowered.boundaries.append(next_boundary)
							Host.apply!(Replace({ old_root: boundary.root, root: lowered.root, nodes: lowered.nodes }))
							install!(next_state, root_renderer, lowered.routes, next_boundaries, lowered.next_id)
						}
					}
				}
				Err(_) => {
					Host.apply!(NoChange)
					install!(state, root_renderer, routes, boundaries, next_id)
				}
			}
		}
		Host.set_dispatch!(Box.box(dispatch!))
	}

	start! : a, (a -> Elem(a)) => {}
	start! = |initial, render| {
		root_renderer = Box.box(render)
		lowered = lower(render(initial), initial, 1, 0, None, [], [], [])
		root_boundary = { key: 0, parent: None, render: root_renderer, root: lowered.root }
		Host.apply!(Mount({ root: lowered.root, nodes: lowered.nodes }))
		install!(initial, root_renderer, lowered.routes, lowered.boundaries.append(root_boundary), lowered.next_id)
	}
}
