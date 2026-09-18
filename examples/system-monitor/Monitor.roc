## Sampling sessions, and the state the window is drawn from.
##
## Nothing is read from the machine until a person asks for it. Asking acquires
## a sampler, starts a timer, and opens a *session*: the pair of resources that
## one run of sampling owns and is responsible for closing. Pausing closes both.
import pf.Program
import pf.Action
import pf.SystemMonitor
import pf.Timer
import Processes

Monitor := [].{
	State : State

	## Where the instrument is, as a state rather than as a sentence. The window
	## turns each of these into the words a person reads, which keeps the
	## vocabulary in one place and keeps a refusal from being just another string
	## in a status field.
	Status : Status

	## How many samples the history holds. The plot's horizontal pitch and the
	## log's bound are the same number, so the two views agree about how far back
	## "the history" reaches.
	capacity : U64
	capacity = capacity

	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Program.Access -> State
	init = |access| { access, filter: "", generation: 0, history: [], latest: None, run_state: Paused, selected: None, sort: ByCpu, status: Idle }

	## Begin a session. Acquisition is the whole authority question: if the host
	## refuses, nothing is opened and nothing is read.
	start! : State => Action.Action(State)
	start! = start!

	## End a session, closing both resources it owns and retiring its generation.
	pause! : State, Session => Action.Action(State)
	pause! = pause!

	Session : Session
	RunState : RunState
}

capacity = 120.U64

Session : { sampler : SystemMonitor.Sampler, timer : Timer.Handle }
RunState : [Paused, Running(Session)]
Status : [Failed(Str), Idle, Live, Paused, Refused]
State : {
	access : Program.Access,
	filter : Str,
	generation : U64,
	history : List(SystemMonitor.Snapshot),
	latest : [None, Some(SystemMonitor.Snapshot)],
	run_state : RunState,
	selected : [None, Some(U64)],
	sort : Processes.Sort,
	status : Status,
}

## A refusal is not a failure, and the window says something quite different
## about each, so they are separated the moment the error arrives rather than
## being flattened into one line of text.
acquire_status = |err| match err {
	AcquireSystemErr(AccessDenied) => Refused
	AcquireSystemErr(ResourceLimit) => Failed("The host has no sampler left to give")
	_ => Failed("System observation could not be started")
}

sample_status = |err| match err {
	SampleSystemErr(Busy) => Failed("A sample is already in progress")
	SampleSystemErr(Closed) => Failed("The sampler was closed while it was sampling")
	SampleSystemErr(Io) => Failed("The system sampler could not be read")
	_ => Failed("System sampling stopped unexpectedly")
}

## A session owns its generation, so a cancelled one cannot pause, fail, or
## extend the session that replaced it.
wait_next = |state, session, generation| Action.task({
	pending: { ..state, run_state: Running(session), status: Live },
	run: || match session.timer.next!() {
		Canceled => Stopped
		Fired => match session.sampler.sample!() {
			Ok(snapshot) => Sampled(snapshot)
			Err(err) => SampleFailed(err)
		}
	},
	resolve: |latest, result| if latest.generation != generation Action.none else match result {
		Stopped => Action.update({ ..latest, run_state: Paused, status: Paused })
		SampleFailed(err) => Action.update({ ..latest, run_state: Paused, status: sample_status(err) })
		Sampled(snapshot) => match latest.run_state {
			Paused => Action.update(latest)
			Running(_) => {
				next = latest.history.append(snapshot)
				bounded = if next.len() > capacity next.drop_first(next.len() - capacity) else next
				wait_next({ ..latest, history: bounded, latest: Some(snapshot) }, session, generation)
			}
		}
	},
})

start! = |state| {
	generation = state.generation + 1
	match SystemMonitor.acquire!(state.access) {
		Err(err) => Action.update({ ..state, status: acquire_status(err) })
		Ok(sampler) => match Timer.start!({ interval_ms: 100 }) {
			Err(_) => {
				_ = sampler.close!()
				Action.update({ ..state, status: Failed("The sampling timer was rejected by the host") })
			}
			Ok(timer) => wait_next({ ..state, generation }, { sampler, timer }, generation)
		}
	}
}

pause! = |state, session| {
	_ = session.timer.cancel!()
	_ = session.sampler.close!()
	Action.update({ ..state, generation: state.generation + 1, run_state: Paused, status: Paused })
}
