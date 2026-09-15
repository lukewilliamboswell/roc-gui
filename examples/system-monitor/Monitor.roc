import pf.Action
import pf.Elem
import pf.Gui
import pf.Timer

Monitor := [].{
	State : State
	init : State
	init = { samples: [], next_sample: 1, run_state: Paused, status: "Paused" }
	render : State -> Elem.Elem(State)
	render = render
}

RunState : [Paused, Running(Timer.Handle)]

State : { samples : List(U64), next_sample : U64, run_state : RunState, status : Str }

wait_next = |state, handle| Action.task({
	pending: { ..state, run_state: Running(handle), status: "Live" },
	run: || Timer.next!(handle),
	resolve: |latest, tick| match tick {
		Canceled => Action.update({ ..latest, run_state: Paused, status: "Paused" })
		Fired => {
			next = latest.samples.append(latest.next_sample)
			bounded = if next.len() > 120 next.drop_first(next.len() - 120) else next
			wait_next({ ..latest, samples: bounded, next_sample: latest.next_sample + 1 }, handle)
		}
	},
})

start! : State => Action.Action(State)
start! = |state| match Timer.start!({ interval_ms: 1 }) {
	Ok(handle) => wait_next(state, handle)
	Err(_) => Action.update({ ..state, status: "Timer configuration rejected" })
}

pause! : State, Timer.Handle => Action.Action(State)
pause! = |state, handle| {
	_ = Timer.cancel!(handle)
	Action.update({ ..state, run_state: Paused, status: "Paused" })
}

sample_items = |samples| {
	var $items = []
	for sample in samples {
		$items = $items.append(Elem.VirtualListItem.{ key: sample, content: Elem.text("Sample ${sample.to_str()}: CPU unavailable; memory unavailable") })
	}
	$items
}

render : State -> Elem.Elem(State)
render = |state| {
	control = match state.run_state {
		Paused => Elem.action_button(Elem.ActionButtonProps.{ caption: "Resume", label: "Resume sampling", on_press: |current, _| start!(current) })
		Running(handle) => Elem.action_button(Elem.ActionButtonProps.{ caption: "Pause", label: "Pause sampling", on_press: |current, _| pause!(current, handle) })
	}
	Elem.col(
		Elem.ColProps.{ label: "System monitor", width: Fill, height: Fill, grow: True, padding: 24 },
		[
			Elem.text("System Monitor"),
			Elem.row(Elem.RowProps.{ label: "Sampling controls" }, [control, Elem.text(state.status)]),
			Elem.panel(Elem.PanelProps.{ label: "Resource summary", width: Fill }, [Elem.text("CPU: unavailable"), Elem.text("Memory: unavailable")]),
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Observation history", row_height: 32, items: sample_items(state.samples) }),
		],
	)
}
