import Work

## The change requested by an event handler. Start with `update` to replace
## state and `none` to leave it unchanged. Use `task` for asynchronous work and
## `delegate` when a parent component must decide whether to accept a change.
##
## A renderer's `curr_state` is a snapshot used to describe the UI. Derive an
## action from the handler's `prev_state`, which is supplied when the event runs:
## `|prev_state, _event| Action.update({ ..prev_state, count: prev_state.count + 1 })`.
## Roc values are immutable. Capturing `curr_state` keeps that snapshot alive
## in the closure, so later updates can require cloning shared storage.
## `prev_state` avoids that extra capture; it does not eliminate cloning when
## other snapshots remain alive. Retained handlers also need their supplied
## state to avoid deriving an action from an older render snapshot.
## Constructing an action alone does not commit state or run a worker.
Action(a) := {
	# Keep recursive callable signatures explicit and pointer-sized at each
	# dynamic argument boundary; the compiler cannot expand recursive aliases here.
	value : [NoChange, Refresh, Update(a), Delegate(a), Deferred(Box(Box((Box(Action(a)) -> Work)) -> Work)), Task({ pending : a, run : Box(Box((Box((Box(a), Box((Box(Action(a)) -> Work)) -> Work)) -> Work)) -> Work) })],
	levels : U64,
}.{

	## Platform continuation receiving state at completion delivery. Applications
	## supply the ordinary `resolve` callback in `task` instead.
	Completion(a) : Box(a), Box((Box(Action(a)) -> Work)) -> Work

	## Platform worker continuation producing a completion for the UI thread.
	Worker(a) : Box((Box(Completion(a)) -> Work)) -> Work

	## Platform projection that can report a removed child without recursing.
	Project(parent, child) : parent, (Try(child, [Removed]) -> Work) -> Work

	## Leave state and the displayed UI unchanged.
	none : Action(a)
	none = Action.{ value: NoChange, levels: 0 }

	## Platform action rendering the originating boundary again against the
	## state it already has. Its ancestors' memo snapshots stay valid, because
	## no state changed; only the boundary's own render inputs from the host did.
	refresh : Action(a)
	refresh = Action.{ value: Refresh, levels: 0 }

	## Request a new state for this render boundary. Derive it from the handler's
	## `prev_state`, not a state snapshot captured by the renderer.
	update : a -> Action(a)
	update = |state| Action.{ value: Update(state), levels: 0 }

	## Propose a child state to the nearest translation's parent policy.
	## The policy may accept, revise, or reject the whole proposed change.
	delegate : a -> Action(a)
	delegate = |state| Action.{ value: Delegate(state), levels: 0 }

	## Accept `pending` before running `run` on a worker. `resolve` receives the
	## state immediately before completion (`prev_state`) and the worker result.
	## Capture only the request data needed by `run`; derive the completion action
	## from `prev_state` so intervening edits survive. Removing the owning component
	## discards its completion, but does not cancel the external operation.
	task : { pending : a, run : (() => result), resolve : (a, result -> Action(a)) } -> Action(a)
	task = |config| {
		run! = config.run
		resolve = config.resolve
		worker_box = worker(
			|done!| Work.next(
				|| {
					result = run!()
					resume = completion(|prev_state, accept!| Work.next(|| accept!(resolve(prev_state, result))))
					Work.next(|| done!(resume))
				},
			),
		)
		Action.{ value: Task({ pending: config.pending, run: worker_box }), levels: 0 }
	}

	## Platform helper deferring action adaptation onto the work executor.
	## This is not an asynchronous task; application I/O belongs in `task`.
	deferred : ((Action(a) -> Work) -> Work) -> Action(a)
	deferred = |resume!| Action.{
		value: Deferred(
			Box.box(
				|done_box| Work.next(
					|| {
						done! = Box.unbox(done_box)
						resume!(|action| Work.next(|| done!(Box.box(action))))
					},
				),
			),
		),
		levels: 0,

	}

	## Platform helper resolving deferred adapters before applying an action.
	resolve_work! : Action(a), (Action(a) -> Work) -> Work
	resolve_work! = |action, done!| {
		levels = owner_levels(action)
		match inspect(action) {
			Deferred(resume) => Work.next(
				|| {
					resume! = Box.unbox(resume)
					resume!(
						Box.box(
							|boxed| Work.next(
								|| {
									next = Box.unbox(boxed)
									resolve_work!(with_levels(next, levels + owner_levels(next)), done!)
								},
							),
						),
					)
				},
			)
			_ => Work.next(|| done!(action))
		}
	}

	## Platform helper packaging a typed completion for the work executor.
	completion : ((a, (Action(a) -> Work) -> Work)) -> Box(Completion(a))
	completion = |resume!| Box.box(
		|state_box, done_box| Work.next(
			|| {
				done! = Box.unbox(done_box)
				resume!(Box.unbox(state_box), |action| Work.next(|| done!(Box.box(action))))
			},
		),
	)

	## Platform helper packaging a worker continuation. Applications use `task`.
	worker : (((Box(Completion(a)) -> Work) -> Work)) -> Box(Worker(a))
	worker = |run!| Box.box(
		|done_box| Work.next(
			|| {
				done! = Box.unbox(done_box)
				run!(done!)
			},
		),
	)

	## Platform helper delivering a completion against the supplied current state.
	complete_work! : Box(Completion(a)), a, (Action(a) -> Work) -> Work
	complete_work! = |resume_box, state, done!| Work.next(
		|| {
			resume! = Box.unbox(resume_box)
			resume!(Box.box(state), Box.box(|action| Work.next(|| done!(Box.unbox(action)))))
		},
	)

	## Platform helper running a worker and forwarding its completion.
	worker_work! : Box(Worker(a)), (Box(Completion(a)) -> Work) -> Work
	worker_work! = |run_box, done!| Work.next(
		|| {
			run! = Box.unbox(run_box)
			run!(Box.box(done!))
		},
	)

	## Reveal the transition for platform dispatch; constructing it has no effect.
	inspect : Action(a) -> [NoChange, Refresh, Update(a), Delegate(a), Deferred(Box(Box((Box(Action(a)) -> Work)) -> Work)), Task({ pending : a, run : Box(Box((Box((Box(a), Box((Box(Action(a)) -> Work)) -> Work)) -> Work)) -> Work) })]
	inspect = |Action.(action)| action.value

	## Platform delegation depth used to find the boundary accepting an action.
	owner_levels : Action(a) -> U64
	owner_levels = |Action.(action)| action.levels

	## Platform helper preserving delegation depth through deferred adapters.
	with_levels : Action(a), U64 -> Action(a)
	with_levels = |Action.(action), levels| Action.{ ..action, levels }

	## Adapt a child action to parent state using a getter and setter.
	## An adapter has no component lifetime and does not consume delegation.
	lift : Action(child), parent, (parent -> child), (parent, child -> parent) -> Action(parent)
	lift = |action, parent, get, set| adapt(action, parent, get, set, None)

	## Platform adapter that lets the enclosing boundary handle delegation.
	through_boundary : Action(child), parent, (parent -> child), (parent, child -> parent), (parent -> Action(parent)) -> Action(parent)
	through_boundary = |action, parent, get, set, delegated| adapt(action, parent, get, set, Some(delegated))

	## Platform adapter shared by `lift` and `through_boundary`.
	adapt : Action(child), parent, (parent -> child), (parent, child -> parent), [None, Some(parent -> Action(parent))] -> Action(parent)
	adapt = |action, parent, get, set, delegated| {
		levels = owner_levels(action)
		project! = |latest, found!| Work.get(|| found!(Ok(get(latest))))
		write = |latest, child| Ok(set(latest, child))
		match inspect(action) {
			NoChange => none
			Refresh => with_levels(refresh, levels)
			Update(child) => with_levels(update(set(parent, child)), levels)
			Delegate(child) => match delegated {
				None => with_levels(delegate(set(parent, child)), levels)
				Some(handle) => {
					accepted = handle(set(parent, child))
					with_levels(accepted, levels + owner_levels(accepted) + 1)
				}
			}
			Deferred(_) => deferred(|done!| adapt_work!(action, parent, project!, write, delegated, done!))
			Task(task_value) => Action.{ value: Task({ pending: set(parent, task_value.pending), run: adapt_worker(task_value.run, project!, write, delegated) }), levels }
		}
	}

	## Platform helper projecting completion-time state before resolving a child task.
	adapt_worker : Box(Worker(child)), Project(parent, child), (parent, child -> Try(parent, [Removed])), [None, Some(parent -> Action(parent))] -> Box(Worker(parent))
	adapt_worker = |child_run, get!, set, delegated| worker(
		|done!| worker_work!(
			child_run,
			|child_complete| Work.next(
				|| {
					resume = completion(
						|latest, accept!| Work.next(
							|| get!(
								latest,
								|projected| match projected {
									Err(_) => Work.next(|| accept!(none))
									Ok(child) => complete_work!(child_complete, child, |child_action| Work.next(|| adapt_work!(child_action, latest, get!, set, delegated, accept!)))
								},
							),
						),
					)
					Work.next(|| done!(resume))
				},
			),
		),
	)

	# Each executed configured setter is tagged once. Missing projections discard
	# the entire candidate, including a proposed delegation or task launch.
	## Platform adapter executing projection and setter work without recursive calls.
	adapt_work! : Action(child), parent, Project(parent, child), (parent, child -> Try(parent, [Removed])), [None, Some(parent -> Action(parent))], (Action(parent) -> Work) -> Work
	adapt_work! = |action, parent, get!, set, delegated, done!| resolve_work!(
		action,
		|resolved| {
			levels = owner_levels(resolved)
			match inspect(resolved) {
				NoChange => Work.next(|| done!(none))
				Refresh => Work.next(|| done!(with_levels(refresh, levels)))
				Update(child) => Work.set(
					|| match set(parent, child) {
						Err(_) => Work.next(|| done!(none))
						Ok(next) => Work.next(|| done!(with_levels(update(next), levels)))
					},
				)
				Delegate(child) => Work.set(
					|| match set(parent, child) {
						Err(_) => Work.next(|| done!(none))
						Ok(candidate) => match delegated {
							None => Work.next(|| done!(with_levels(delegate(candidate), levels)))
							Some(handle) => Work.next(|| resolve_work!(handle(candidate), |accepted| Work.next(|| done!(with_levels(accepted, levels + owner_levels(accepted) + 1)))))
						}
					},
				)
				Task(task_value) => Work.set(
					|| match set(parent, task_value.pending) {
						Err(_) => Work.next(|| done!(none))
						Ok(pending) => Work.next(|| done!(Action.{ value: Task({ pending, run: adapt_worker(task_value.run, get!, set, delegated) }), levels }))
					},
				)
				Deferred(_) => crash "unresolved action reached adapter"
			}
		},
	)
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

expect {
	# Delegation crosses real boundaries while ordinary adapters preserve it.
	inner = Action.through_boundary(Action.delegate(2.I64), { value: 1.I64 }, |state| state.value, |state, value| { ..state, value }, |candidate| Action.delegate({ ..candidate, value: candidate.value + 1 }))
	outer = Action.through_boundary(inner, { child: { value: 1.I64 }, accepted: False }, |state| state.child, |state, child| { ..state, child }, |candidate| Action.update({ ..candidate, accepted: True }))
	match Action.inspect(outer) {
		Update(next) => next.child.value == 3 and next.accepted and Action.owner_levels(outer) == 2
		_ => False
	}
}

expect {
	inner = Action.through_boundary(Action.delegate(2.I64), { value: 1.I64 }, |state| state.value, |state, value| { ..state, value }, Action.delegate)
	outer = Action.through_boundary(inner, { child: { value: 1.I64 } }, |state| state.child, |state, child| { ..state, child }, |_| Action.none)
	match Action.inspect(outer) {
		NoChange => True
		_ => False
	}
}
