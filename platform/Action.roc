## A state transition returned by an element event handler. Applications usually
## construct one with `Action.update`, `Action.none`, or `Action.task`.
ActionValue(a) := [
	NoChange,
	Task({ pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) }),
	Update(a),
].{

	## The representation of an action that leaves state unchanged.
	none : ActionValue(a)
	none = NoChange

	## The representation of an immediate state replacement.
	update : a -> ActionValue(a)
	update = |value| Update(value)

	## The representation of an asynchronous state transition.
	task : { pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) } -> ActionValue(a)
	task = |value| Task(value)

	## Reveal the platform representation of an action value.
	inspect : ActionValue(a) -> [NoChange, Task({ pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) }), Update(a)]
	inspect = |value| match value {
		NoChange => NoChange
		Task(task_value) => Task(task_value)
		Update(next) => Update(next)
	}
}

## An event handler's requested transition for application state `a`.
Action(a) :: [Action(ActionValue(a))].{

	## Replace application state immediately.
	update : a -> Action(a)
	update = |value| Action(ActionValue.update(value))

	## Leave application state and the rendered tree unchanged.
	none : Action(a)
	none = Action(ActionValue.none)

	## Commit `pending` immediately, run `run` on a worker thread, then call
	## `resolve` with the latest application state on the UI thread. This lets
	## other events update state while the task is running without being lost.
	task : { pending : a, run : (() => result), resolve : (a, result -> Action(a)) } -> Action(a)
	task = |config| {
		run! = config.run
		resolve = config.resolve
		worker! = || {
			result = run!()
			complete = |latest_box| Box.box(resolve(Box.unbox(latest_box), result))
			Box.box(complete)
		}
		result : Action(a)
		result = Action(ActionValue.task({ pending: config.pending, run: Box.box(worker!) }))
		result
	}

	## Adapt an action over component state to its owning application state.
	lift : Action(child), parent, (parent -> child), (parent, child -> parent) -> Action(parent)
	lift = |action, parent, get_child, set_child| match inspect(action) {
		NoChange => none
		Update(next_child) => update(set_child(parent, next_child))
		Task(task_value) => {
			child_worker_box = task_value.run
			parent_worker! = || {
				child_worker! = Box.unbox(child_worker_box)
				child_complete_box = child_worker!()
				parent_complete = |latest_parent_box| {
					latest_parent = Box.unbox(latest_parent_box)
					child_complete = Box.unbox(child_complete_box)
					child_action = Box.unbox(child_complete(Box.box(get_child(latest_parent))))
					Box.box(lift(child_action, latest_parent, get_child, set_child))
				}
				Box.box(parent_complete)
			}
			result : Action(parent)
			result = Action(
				ActionValue.task({
					pending: set_child(parent, task_value.pending),
					run: Box.box(parent_worker!),
				}),
			)
			result
		}
	}

	## Reveal an action's platform representation. Application UI normally uses
	## the constructors instead; this is useful when building state adapters.
	inspect : Action(a) -> [NoChange, Task({ pending : a, run : Box((() => Box((Box(a) -> Box(Action(a)))))) }), Update(a)]
	inspect = |Action(value)| ActionValue.inspect(value)
}
