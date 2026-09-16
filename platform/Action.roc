## An immutable transition. Constructing an action does not commit state or run
## its worker. Delegation constructs a candidate parent and may be vetoed.
Action(a) := {
	value : [NoChange, Update(a), Delegate(a), Task({ pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) })],
	levels : U64,
}.{
	none : Action(a)
	none = Action.{ value: NoChange, levels: 0 }

	update : a -> Action(a)
	update = |state| Action.{ value: Update(state), levels: 0 }

	delegate : a -> Action(a)
	delegate = |state| Action.{ value: Delegate(state), levels: 0 }

	task : { pending : a, run : (() => result), resolve : (a, result -> Action(a)) } -> Action(a)
	task = |config| {
		run! = config.run
		resolve = config.resolve
		worker! = || {
			result = run!()
			complete = |latest| Box.box(resolve(Box.unbox(latest), result))
			Box.box(complete)
		}
		Action.{ value: Task({ pending: config.pending, run: Box.box(worker!) }), levels: 0 }
	}

	inspect : Action(a) -> [NoChange, Update(a), Delegate(a), Task({ pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) })]
	inspect = |Action.(action)| action.value

	owner_levels : Action(a) -> U64
	owner_levels = |Action.(action)| action.levels

	with_levels : Action(a), U64 -> Action(a)
	with_levels = |Action.(action), levels| Action.{ ..action, levels }

	## An adapter has no component lifetime and does not consume delegation.
	lift : Action(child), parent, (parent -> child), (parent, child -> parent) -> Action(parent)
	lift = |action, parent, get, set| adapt(action, parent, get, set, None)

	## Cross one actual component boundary. The callback receives a candidate;
	## its returned action decides whether that proposal is accepted.
	through_boundary : Action(child), parent, (parent -> child), (parent, child -> parent), (parent -> Action(parent)) -> Action(parent)
	through_boundary = |action, parent, get, set, delegated| adapt(action, parent, get, set, Some(delegated))

	adapt : Action(child), parent, (parent -> child), (parent, child -> parent), [None, Some(parent -> Action(parent))] -> Action(parent)
	adapt = |action, parent, get, set, delegated| {
		levels = owner_levels(action)
		match inspect(action) {
			NoChange => none
			Update(child) => with_levels(update(set(parent, child)), levels)
			Delegate(child) => match delegated {
				None => with_levels(delegate(set(parent, child)), levels)
				Some(handle) => {
					accepted = handle(set(parent, child))
					with_levels(accepted, levels + owner_levels(accepted) + 1)
				}
			}
			Task(task_value) => {

				## Capture only the worker, never the task record's pending state.
				child_run = task_value.run
				worker! = || {
					child_worker! = Box.unbox(child_run)
					child_complete = Box.unbox(child_worker!())
					complete = |latest_box| {
						latest = Box.unbox(latest_box)
						child_action = Box.unbox(child_complete(Box.box(get(latest))))
						Box.box(adapt(child_action, latest, get, set, delegated))
					}
					Box.box(complete)
				}
				Action.{ value: Task({ pending: set(parent, task_value.pending), run: Box.box(worker!) }), levels }
			}
		}
	}
}

expect {
	parent = { child: 1.I64, saved: 0.I64 }
	get = |state| state.child
	set = |state, child| { ..state, child }
	proposal = Action.lift(Action.delegate(2.I64), parent, get, set)
	match Action.inspect(proposal) {
		Delegate(candidate) => candidate.child == 2 and Action.owner_levels(proposal) == 0
		_ => False
	}
}

expect {
	parent = { child: 1.I64, saved: 0.I64 }
	get = |state| state.child
	set = |state, child| { ..state, child }
	accepted = Action.through_boundary(Action.delegate(2.I64), parent, get, set, |candidate| Action.update({ ..candidate, saved: candidate.child }))
	match Action.inspect(accepted) {
		Update(next) => next.child == 2 and next.saved == 2 and Action.owner_levels(accepted) == 1
		_ => False
	}
}

expect {
	parent = { child: 1.I64 }
	vetoed = Action.through_boundary(Action.delegate(2.I64), parent, |state| state.child, |state, child| { ..state, child }, |_| Action.none)
	match Action.inspect(vetoed) {
		NoChange => True
		_ => False
	}
}
