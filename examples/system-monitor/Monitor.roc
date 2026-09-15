import pf.Action
import pf.Elem
import pf.SystemMonitor
import pf.Timer
import Processes
import Summary

Monitor := [].{
	State : State
	init : State
	init = { filter: "", history: [], latest: None, run_state: Paused, selected: None, sort: ByCpu, status: "Paused" }
	render : State -> Elem.Elem(State)
	render = render
}

RunState : [Paused, Running({ sampler : SystemMonitor.Sampler, timer : Timer.Handle })]
State : { filter : Str, history : List(SystemMonitor.Snapshot), latest : [None, Some(SystemMonitor.Snapshot)], run_state : RunState, selected : [None, Some(U64)], sort : Processes.Sort, status : Str }
err_text = |err| match err { AcquireSystemErr(AccessDenied) => "System observation access denied", SampleSystemErr(Busy) => "A sample is already in progress", SampleSystemErr(Closed) => "Sampler closed", _ => "System sampling failed" }

wait_next = |state, session| Action.task({
	pending: { ..state, run_state: Running(session), status: "Live" },
	run: || match Timer.next!(session.timer) { Canceled => Stopped, Fired => match SystemMonitor.sample!(session.sampler) { Ok(snapshot) => Sampled(snapshot), Err(err) => SampleFailed(err) } },
	resolve: |latest, result| match result {
		Stopped => Action.update({ ..latest, run_state: Paused, status: "Paused" })
		SampleFailed(err) => Action.update({ ..latest, run_state: Paused, status: err_text(err) })
		Sampled(snapshot) => match latest.run_state {
			Paused => Action.update(latest)
			Running(_) => {
				next = latest.history.append(snapshot)
				bounded = if next.len() > 120 next.drop_first(next.len() - 120) else next
				wait_next({ ..latest, history: bounded, latest: Some(snapshot) }, session)
			}
		}
	},
})

start! = |state| match SystemMonitor.acquire!() {
	Err(err) => Action.update({ ..state, status: err_text(err) })
	Ok(sampler) => match Timer.start!({ interval_ms: 1 }) {
		Err(_) => {
			_ = SystemMonitor.close!(sampler)
			Action.update({ ..state, status: "Timer configuration rejected" })
		}
		Ok(timer) => wait_next(state, { sampler, timer })
	}
}
pause! = |state, session| {
	_ = Timer.cancel!(session.timer)
	_ = SystemMonitor.close!(session.sampler)
	Action.update({ ..state, run_state: Paused, status: "Paused" })
}
history_items = |history| history.map(|snapshot| Elem.VirtualListItem.{ key: snapshot.sequence, content: Elem.text(Summary.history_text(snapshot)) })
process_items = |state, processes| Processes.filter_sort(processes, state.filter, state.sort).map(|process| Elem.VirtualListItem.{ key: process.pid, content: Elem.action_button(Elem.ActionButtonProps.{ caption: "${process.name} — CPU ${(process.cpu_tenths / 10).to_str()}.${(process.cpu_tenths % 10).to_str()}%, ${process.memory_bytes.to_str()} bytes", label: "Inspect process ${process.name}", on_press: |current, _| Action.update({ ..current, selected: Some(process.pid) }) }) })

process_panel = |state| match state.latest {
	None => Elem.panel(Elem.PanelProps.{ label: "Processes", width: Fill }, [Elem.text("Processes: no sample")])
	Some(snapshot) => match snapshot.processes {
		Unavailable(_) => Elem.panel(Elem.PanelProps.{ label: "Processes", width: Fill }, [Elem.text("Processes: unavailable")])
		Value(processes) => {
			selection = match state.selected { None => "No process selected", Some(pid) => "Selected process ${pid.to_str()}" }
			Elem.panel(Elem.PanelProps.{ label: "Processes", width: Fill, height: Fill, grow: True }, [
				Elem.row(Elem.RowProps.{ label: "Process sorting" }, [
					Elem.action_button(Elem.ActionButtonProps.{ caption: "CPU", label: "Sort processes by CPU", on_press: |current, _| Action.update({ ..current, sort: ByCpu }) }),
					Elem.action_button(Elem.ActionButtonProps.{ caption: "Memory", label: "Sort processes by memory", on_press: |current, _| Action.update({ ..current, sort: ByMemory }) }),
				]),
				Elem.text_input(Elem.TextInputProps.{ label: "Filter processes", value: state.filter, on_change: |current, event| Action.update({ ..current, filter: event.value }), on_submit: |current, _| Action.update(current), width: Fill }),
				Elem.text("Processes: ${List.len(processes).to_str()}"), Elem.text(selection),
				Elem.virtual_list(Elem.VirtualListProps.{ name: "Process table", row_height: 34, items: process_items(state, processes) }),
			])
	}
}
}

render = |state| {
	control = match state.run_state { Paused => Elem.action_button(Elem.ActionButtonProps.{ caption: "Resume", label: "Resume sampling", on_press: |current, _| start!(current) }), Running(session) => Elem.action_button(Elem.ActionButtonProps.{ caption: "Pause", label: "Pause sampling", on_press: |current, _| pause!(current, session) }) }
	summary = match state.latest { None => Elem.panel(Elem.PanelProps.{ label: "Resource summary", width: Fill }, [Elem.text("CPU: no sample"), Elem.text("Memory: no sample")]), Some(snapshot) => Summary.render(snapshot) }
	Elem.col(Elem.ColProps.{ label: "System monitor", width: Fill, height: Fill, grow: True, padding: 24, gap: 12 }, [Elem.text("System Monitor"), Elem.row(Elem.RowProps.{ label: "Sampling controls" }, [control, Elem.text(state.status)]), summary, process_panel(state), Elem.virtual_list(Elem.VirtualListProps.{ name: "Observation history", row_height: 32, items: history_items(state.history) })])
}
