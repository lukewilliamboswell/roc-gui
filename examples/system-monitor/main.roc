app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Gui
import pf.Layout
import pf.Program exposing [Program]
import pf.Timer

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

invalid_start! : State => Action.Action(State)
invalid_start! = |state| match Timer.start!({ interval_ms: 0 }) {
	Err(_) => Action.update({ ..state, status: "Invalid interval rejected" })
	Ok(handle) => {
		_ = Timer.cancel!(handle)
		Action.update({ ..state, status: "Invalid interval accepted" })
	}
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
	Layout.col(
		Elem.ColProps.{ label: "System monitor", width: Fill, height: Fill, grow: True, padding: 24 },
		[
			Elem.text("System Monitor"),
			Layout.row(Elem.RowProps.{ label: "Sampling controls" }, [control, Elem.action_button(Elem.ActionButtonProps.{ caption: "Validate bounds", label: "Validate timer bounds", on_press: |current, _| invalid_start!(current) }), Elem.text(state.status)]),
			Elem.panel(Elem.PanelProps.{ label: "Resource summary", width: Fill }, [Elem.text("CPU: unavailable"), Elem.text("Memory: unavailable")]),
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Observation history", row_height: 32, items: sample_items(state.samples) }),
		],
	)
}

main : Program(State)
main = Program.run({
	init: { samples: [], next_sample: 1, run_state: Paused, status: "Paused" },
	render,
	window: { title: "System Monitor", width: 800, height: 600 },
})
