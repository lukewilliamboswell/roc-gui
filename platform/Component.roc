import Action
import Elem
import Host

## A definition is created once during setup. Rendering supplies only its key;
## its renderer, adapters and delegation policy cannot change between renders.
Component(parent) := { bind : Elem.Key -> Elem(parent) }.{
	Config(parent, child) := {
		get : parent, Elem.Key -> Try(child, [Removed]),
		set : parent, Elem.Key, child -> Try(parent, [Removed]),
		render : child -> Elem(child),
		update_scope : [Local, Parent] ?? Local,
		on_delegate : parent, Elem.Key -> Action(parent) ?? |parent, _| Action.update(parent),
	}
	MemoConfig(parent, child) := {
		get : parent, Elem.Key -> Try(child, [Removed]),
		set : parent, Elem.Key, child -> Try(parent, [Removed]),
		render : child -> Elem(child),
		same : child, child -> Bool,
		update_scope : [Local, Parent] ?? Local,
		on_delegate : parent, Elem.Key -> Action(parent) ?? |parent, _| Action.update(parent),
	}

	## Equal child inputs retain the mounted subtree and its captured handlers.
	## Equality must preserve both rendering and handler behavior.
	define! : Config(parent, child) => Component(parent) where [child.is_eq : child, child -> Bool]
	define! = |Config.(config)| build!(config.get, config.set, config.render, Some(|previous, next| previous == next), config.update_scope, config.on_delegate)

	## Always render when this boundary is reached. Use for inputs without a
	## suitable equality or when comparison and snapshot retention cost more.
	unmemoized! : Config(parent, child) => Component(parent)
	unmemoized! = |Config.(config)| build!(config.get, config.set, config.render, None, config.update_scope, config.on_delegate)

	## True must preserve both rendering and captured-handler behavior. Retaining
	## a snapshot can inhibit in-place state updates. Use this constructor only
	## when the input's ordinary equality is not the desired memo equivalence.
	memo! : MemoConfig(parent, child) => Component(parent)
	memo! = |MemoConfig.(config)| build!(config.get, config.set, config.render, Some(config.same), config.update_scope, config.on_delegate)

	mount : Component(parent), Elem.Key -> Elem(parent)
	mount = |Component.(definition), key| (definition.bind)(key)

	build! : (parent, Elem.Key -> Try(child, [Removed])), (parent, Elem.Key, child -> Try(parent, [Removed])), (child -> Elem(child)), [None, Some((child, child -> Bool))], [Local, Parent], (parent, Elem.Key -> Action(parent)) => Component(parent)
	build! = |project, replace, render, same, update_scope, delegated| {
		definition = Host.component_define!()
		bind = |key| {
			get = |parent| project(parent, key) ?? crash "component state was removed"
			set = |parent, child| replace(parent, key, child) ?? crash "component setter cannot recreate removed state"
			remember = match same {
				None => None
				Some(compare) => Some(
					|parent| {
						previous = get(parent)
						Box.box(|next| compare(previous, get(next)))
					},
				)
			}
			Elem.bound_component(
				Elem.BoundComponent.{
					definition,
					key,
					render: |parent| Elem.lift_with(render(get(parent)), get, set, |action, latest| Action.through_boundary(action, latest, get, set, |candidate| delegated(candidate, key))),
					exists: |parent| match project(parent, key) {
						Ok(_) => True
						Err(_) => False
					},
					remember,
					update_scope,
				},
			)
		}
		Component.{ bind }
	}
}
