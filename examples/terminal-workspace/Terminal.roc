import pf.Action
import pf.Elem
import pf.Process
import Theme

Terminal := [].{
	State : State
	init : State
	init = { command: "", generation: 0, lines: [], phase: Idle, query: "", status: "No session" }
	start : State -> Action.Action(State)
	start = start
	cancel : State -> Action.Action(State)
	cancel = cancel
	set_command : State, Str -> State
	set_command = |state, command| { ..state, command }
	set_query : State, Str -> State
	set_query = |state, query| { ..state, query }
	submit : State, Str -> Action.Action(State)
	submit = submit
	render : State -> Elem.Elem(State)
	render = render
}

Phase : [Idle, Live({ pty : Process.Pty, reading : Bool }), Starting, Stopped]
State : { command : Str, generation : U64, lines : List(Str), phase : Phase, query : Str, status : Str }

set_command = |state, command| { ..state, command }
set_query = |state, query| { ..state, query }

err_message = |err| match err {
	AcquireProcessErr(AccessDenied) => "Process access denied"
	SpawnProcessErr(InvalidSize) => "Terminal size rejected"
	ReadProcessErr(Busy) => "A read is already pending"
	ReadProcessErr(InvalidCapability) => "Stale terminal handle"
	ReadProcessErr(Exited) => "Process exited"
	WriteProcessErr(Exited) => "Process exited"
	_ => "Terminal operation failed"
}

append_bytes = |state, bytes| match Str.from_utf8(bytes) {
	Err(_) => { ..state, status: "Invalid UTF-8 from child" }
	Ok(text) => { ..state, lines: state.lines.concat(Str.split_on(text, "\n")), status: "Session active" }
}

read_next = |state, pty, generation| Action.task({
	pending: { ..state, phase: Live({ pty, reading: True }) },
	run: || Process.read!(pty, { max_bytes: 65536 }),
	resolve: |latest, result| if latest.generation != generation {
		Action.none
	} else {
		match result {
			Err(err) => Action.update({ ..latest, phase: Stopped, status: err_message(err) })
			Ok(Canceled) => Action.update({ ..latest, phase: Stopped, status: "Session canceled" })
			Ok(EndOfFile) => Action.update({ ..latest, phase: Stopped, status: "Process exited" })
			Ok(Data(bytes)) => read_next(append_bytes(latest, bytes), pty, generation)
		}
	},
})

start : State -> Action.Action(State)
start = |state| {
	next_generation = state.generation + 1
	Action.task({
		pending: { ..state, generation: next_generation, lines: [], phase: Starting, status: "Starting session" },
		run: || match Process.acquire!({}) {
			Err(err) => StartFailed(err)
			Ok(grant) => match Process.spawn!(grant, { columns: 100, rows: 30 }) {
				Err(err) => StartFailed(err)
				Ok(pty) => Started(pty)
			}
		},
		resolve: |latest, result| if latest.generation != next_generation {
			Action.none
		} else {
			match result {
				StartFailed(err) => Action.update({ ..latest, phase: Idle, status: err_message(err) })
				Started(pty) => read_next({ ..latest, phase: Live({ pty, reading: False }), status: "Session active" }, pty, next_generation)
			}
		},
	})
}

submit : State, Str -> Action.Action(State)
submit = |state, command| match state.phase {
	Live(session) => Action.task({
		pending: { ..state, command: "", status: "Sending command" },
		run: || Process.write!(session.pty, "${command}\n".to_utf8()),
		resolve: |latest, result| match result {
			Err(err) => Action.update({ ..latest, status: err_message(err) })
			Ok(_) => Action.update({ ..latest, status: "Command sent" })
		},
	})
	_ => Action.update({ ..state, status: "Start a session first" })
}

cancel : State -> Action.Action(State)
cancel = |state| match state.phase {
	Live(session) => {
		next_generation = state.generation + 1
		Action.task({
			pending: { ..state, generation: next_generation, status: "Stopping session" },
			run: || Process.cancel!(session.pty),
			resolve: |latest, result| match result {
				Err(err) => Action.update({ ..latest, phase: Stopped, status: err_message(err) })
				Ok(_) => Action.update({ ..latest, phase: Stopped, status: "Session canceled" })
			},
		})
	}
	_ => Action.update({ ..state, status: "No live session" })
}

visible_lines = |state| {
	var $items = []
	var $key = 0
	for line in state.lines {
		matches = Str.is_empty(state.query) or Str.contains(line, state.query)
		if matches {
			$items = $items.append(Elem.VirtualListItem.{ key: $key, content: Elem.text("Terminal line: ${line}") })
		}
		$key = $key + 1
	}
	$items
}

key_cap = |caption, label, enabled, on_press| Elem.action_button(Elem.ActionButtonProps.{
	caption,
	label,
	enabled,
	on_press,
	padding: 5,
	font_size: Theme.meta,
	radius: Theme.radius,
	bg: Theme.key,
	hover_bg: Theme.key_hover,
	active_bg: Theme.key_active,
	fg: Theme.text,
	border_color: Theme.edge,
	border_width: 1,
})

field_row = |label, caption, field| Elem.row(
	Elem.RowProps.{ label, width: Fill, padding: Theme.inset, gap: Theme.inset, bg: Theme.region, border_color: Theme.line, border_width: 1, radius: Theme.radius },
	[
		Elem.row(Elem.RowProps.{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta }, [Elem.text(caption)]),
		field,
	],
)

render : State -> Elem.Elem(State)
render = |state| {
	live = match state.phase {
		Live(_) => True
		_ => False
	}
	shown = visible_lines(state)
	filtered = if Str.is_empty(state.query) { "filter off" } else { "filter \"${state.query}\"" }
	Elem.col(Elem.ColProps.{ label: "Terminal pane", width: Fill, height: Fill, grow: True, gap: Theme.seam, fg: Theme.text, font_size: Theme.body }, [
		Elem.row(Elem.RowProps.{ label: "Session controls", width: Fill, padding: Theme.inset, gap: Theme.inset, bg: Theme.region, border_color: Theme.line, border_width: 1, radius: Theme.radius }, [
			key_cap("New terminal", "New terminal", !live, |current, _| start(current)),
			key_cap("Stop", "Stop terminal", live, |current, _| cancel(current)),
			Elem.row(Elem.RowProps.{ label: "Session status", padding: 4, gap: 0, grow: True, justify: End, fg: Theme.signal, font_size: Theme.meta }, [Elem.text(state.status)]),
		]),
		field_row("Command bar", "cmd", Elem.text_input(Elem.TextInputProps.{ label: "Terminal command", value: state.command, placeholder: "type a command, press enter", enabled: live, on_change: |current, event| Action.update(set_command(current, event.value)), on_submit: |current, event| submit(current, event.value), grow: True, width: Fill, height: Px(26), padding: Theme.inset, font_size: Theme.body, bg: Theme.well, fg: Theme.text, border_color: Theme.edge, border_width: 1, radius: Theme.radius })),
		field_row("Filter bar", "find", Elem.text_input(Elem.TextInputProps.{ label: "Search terminal", value: state.query, placeholder: "filter scrollback", on_change: |current, event| Action.update(set_query(current, event.value)), on_submit: |current, _| Action.update(current), grow: True, width: Fill, height: Px(26), padding: Theme.inset, font_size: Theme.body, bg: Theme.well, fg: Theme.text, border_color: Theme.edge, border_width: 1, radius: Theme.radius })),
		Elem.col(Elem.ColProps.{ label: "Scrollback well", width: Fill, height: Fill, grow: True, padding: 4, gap: 0, bg: Theme.well, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip }, [
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Terminal scrollback", row_height: Theme.row_height, items: shown }),
		]),
		Elem.row(Elem.RowProps.{ label: "Workspace footer", width: Fill, padding: Theme.inset, gap: 8, bg: Theme.region, border_color: Theme.line, border_width: 1, radius: Theme.radius, fg: Theme.dim, font_size: Theme.meta }, [
			Elem.text("${shown.len().to_str()}/${state.lines.len().to_str()} lines"),
			Elem.text("|"),
			Elem.text(filtered),
			Elem.text("|"),
			Elem.text("gen ${state.generation.to_str()}"),
		]),
	])
}
