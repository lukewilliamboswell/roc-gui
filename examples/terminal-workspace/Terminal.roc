import pf.Action
import pf.Elem
import pf.Process

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

## Keeps the printable text of a terminal byte stream. Programs in a PTY may
## emit VT control sequences, and a Windows pseudo console renders all output
## with cursor, erase, and title sequences, so scrollback shows only the text.
plain_text = |bytes| {
	var $text = []
	var $mode = 0
	for byte in bytes {
		if $mode == 1 {
			$mode = if byte == 91 { 2 } else if byte == 93 { 3 } else { 0 }
		} else if $mode == 2 {
			if byte >= 64 and byte <= 126 {
				$mode = 0
			}
		} else if $mode == 3 {
			if byte == 7 {
				$mode = 0
			} else if byte == 27 {
				$mode = 1
			}
		} else if byte == 27 {
			$mode = 1
		} else if byte != 13 {
			$text = $text.append(byte)
		}
	}
	$text
}

append_bytes = |state, bytes| match Str.from_utf8(plain_text(bytes)) {
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

render : State -> Elem.Elem(State)
render = |state| {
	live = match state.phase {
		Live(_) => True
		_ => False
	}
	Elem.col(Elem.ColProps.{ label: "Terminal pane", width: Fill, height: Fill, grow: True, gap: 12 }, [
		Elem.row(Elem.RowProps.{ label: "Session controls" }, [
			Elem.action_button(Elem.ActionButtonProps.{ caption: "New terminal", label: "New terminal", enabled: !live, on_press: |current, _| start(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Stop", label: "Stop terminal", enabled: live, on_press: |current, _| cancel(current) }),
			Elem.text(state.status),
		]),
		Elem.row(Elem.RowProps.{ label: "Command controls", width: Fill }, [
			Elem.text_input(Elem.TextInputProps.{ label: "Terminal command", value: state.command, enabled: live, on_change: |current, event| Action.update(set_command(current, event.value)), on_submit: |current, event| submit(current, event.value), grow: True }),
		]),
		Elem.text_input(Elem.TextInputProps.{ label: "Search terminal", value: state.query, on_change: |current, event| Action.update(set_query(current, event.value)), on_submit: |current, _| Action.update(current), width: Fill }),
		Elem.virtual_list(Elem.VirtualListProps.{ name: "Terminal scrollback", row_height: 28, items: visible_lines(state) }),
	])
}
