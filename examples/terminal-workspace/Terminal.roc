import pf.Action
import pf.Elem
import pf.Process
import Theme
import "icons/terminal.svg" as prompt_icon : List(U8)
import "icons/search.svg" as search_icon : List(U8)

Terminal := [].{
	State : State
	init : State
	init = { command: "", generation: 0, lines: [], phase: Idle, query: "", status: "No session", tone: Rest }
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

## A status line carries a tone as well as a sentence. Amber says the panel is
## attached to a child; red says an operation was refused or failed; dim says
## the panel is simply at rest. Without the tone the three read identically and
## the one colour in the palette stops meaning anything.
Tone : [Rest, Attached, Refused]

State : { command : Str, generation : U64, lines : List(Str), phase : Phase, query : Str, status : Str, tone : Tone }

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
	Err(_) => { ..state, status: "Invalid UTF-8 from child", tone: Refused }
	Ok(text) => { ..state, lines: state.lines.concat(Str.split_on(text, "\n")), status: "Session active", tone: Attached }
}

read_next = |state, pty, generation| Action.task({
	pending: { ..state, phase: Live({ pty, reading: True }) },
	run: || pty.read!({ max_bytes: 65536 }),
	resolve: |latest, result| if latest.generation != generation {
		Action.none
	} else {
		match result {
			Err(err) => Action.update({ ..latest, phase: Stopped, status: err_message(err), tone: Refused })
			Ok(Canceled) => Action.update({ ..latest, phase: Stopped, status: "Session canceled", tone: Rest })
			Ok(EndOfFile) => Action.update({ ..latest, phase: Stopped, status: "Process exited", tone: Rest })
			Ok(Data(bytes)) => read_next(append_bytes(latest, bytes), pty, generation)
		}
	},
})

start : State -> Action.Action(State)
start = |state| {
	next_generation = state.generation + 1
	Action.task({
		pending: { ..state, generation: next_generation, lines: [], phase: Starting, status: "Starting session", tone: Attached },
		run: || match Process.acquire!() {
			Err(err) => StartFailed(err)
			Ok(grant) => match grant.spawn!({ columns: 100, rows: 30 }) {
				Err(err) => StartFailed(err)
				Ok(pty) => Started(pty)
			}
		},
		resolve: |latest, result| if latest.generation != next_generation {
			Action.none
		} else {
			match result {
				StartFailed(err) => Action.update({ ..latest, phase: Idle, status: err_message(err), tone: Refused })
				Started(pty) => read_next({ ..latest, phase: Live({ pty, reading: False }), status: "Session active", tone: Attached }, pty, next_generation)
			}
		},
	})
}

submit : State, Str -> Action.Action(State)
submit = |state, command| match state.phase {
	Live(session) => Action.task({
		pending: { ..state, command: "", status: "Sending command", tone: Attached },
		run: || session.pty.write!("${command}\n".to_utf8()),
		resolve: |latest, result| match result {
			Err(err) => Action.update({ ..latest, status: err_message(err), tone: Refused })
			Ok(_) => Action.update({ ..latest, status: "Command sent", tone: Attached })
		},
	})
	_ => Action.update({ ..state, status: "Start a session first", tone: Refused })
}

cancel : State -> Action.Action(State)
cancel = |state| match state.phase {
	Live(session) => {
		next_generation = state.generation + 1
		Action.task({
			pending: { ..state, generation: next_generation, status: "Stopping session", tone: Attached },
			run: || session.pty.cancel!(),
			resolve: |latest, result| match result {
				Err(err) => Action.update({ ..latest, phase: Stopped, status: err_message(err), tone: Refused })
				Ok(_) => Action.update({ ..latest, phase: Stopped, status: "Session canceled", tone: Rest })
			},
		})
	}
	_ => Action.update({ ..state, status: "No live session", tone: Refused })
}

## One scrollback row holds exactly what the child wrote. An earlier version
## prefixed every row with "Terminal line: " — an accessibility name that leaked
## into the visible column and doubled the width of forty characters of output.
visible_lines = |state| {
	var $items = []
	var $key = 0
	for line in state.lines {
		matches = Str.is_empty(state.query) or Str.contains(line, state.query)
		if matches {
			$items = $items.append(Elem.VirtualListItem.{ key: $key, content: Elem.text(line) })
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

## The gutter mark of a field bar. A prompt caret says "this line is sent to the
## shell" and a lens says "this line only filters what is already here"; both
## read faster than the three-letter captions they replace, and at the dim
## weight of the panel's own labels.
gutter_mark = |bytes, name| Elem.image(Elem.ImageProps.{ label: name, bytes, format: Svg, width: Px(13), height: Px(13) })

field_row = |label, mark, field| Elem.row(
	Elem.RowProps.{ label, width: Fill, padding: Theme.inset, gap: Theme.inset, bg: Theme.region, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
	[mark, field],
)

## The panel at rest is otherwise a black rectangle the height of the window.
## An instrument that is not reading anything should say so, and say what would
## make it read: the same sentence a person needs is the sentence that fills the
## well. Each state names what happened, what it means, and the next move.
placard = |tone, headline, detail| Elem.col(
	Elem.ColProps.{
		label: "Scrollback placard",
		width: Fill,
		height: Fill,
		grow: True,
		gap: 6,
		padding: 24,
		align: Center,
		justify: Center,
	},
	[
		Elem.col(
			Elem.ColProps.{ font_size: 13, fg: tone },
			[Elem.text(headline)],
		),
		Elem.col(
			Elem.ColProps.{ max_width: Px(420), font_size: Theme.meta, fg: Theme.dim },
			[Elem.text(detail)],
		),
	],
)

## What the well shows when it has no rows to show. The distinction that matters
## is between "nothing has run" and "something was refused": the first is the
## resting state of a fresh window, the second is a wall the person has to be
## told how to get past, so it names the exact grant the workspace was denied.
empty_well = |state| {
	filtering = !Str.is_empty(state.query)
	total = state.lines.len().to_str()
	refused = match state.tone {
		Refused => True
		_ => False
	}
	match state.phase {
		_ if filtering and state.lines.len() > 0 =>
			placard(Theme.text, "No line matches “${state.query}”", "${total} lines are held in scrollback. Clear the filter to see them all.")
		## The headline is never a copy of the status readout in the controls
		## row. That row reports what the last operation did; the placard says
		## what the empty well means and what to do about it.
		Idle if refused =>
			placard(Theme.alarm, "No shell was granted", "This workspace spawns a shell only through a grant it was launched with. Start it with --host-cap-process=local-shell, or =test-program for the deterministic child, then press New terminal.")
		Idle =>
			placard(Theme.dim, "Nothing attached", "Press New terminal to attach a pseudo-terminal to this panel. Nothing is spawned until you do.")
		Starting =>
			placard(Theme.signal, "Attaching…", "Acquiring the process grant and spawning a 100×30 pseudo-terminal.")
		Live(_) =>
			placard(Theme.signal, "Waiting for output", "The child is attached and has written nothing yet. Type a command in the bar above.")
		Stopped =>
			placard(Theme.dim, "Session ended", "Scrollback from that session is gone. Press New terminal to start another.")
	}
}

render : State -> Elem.Elem(State)
render = |state| {
	live = match state.phase {
		Live(_) => True
		_ => False
	}
	shown = visible_lines(state)
	filtered = if Str.is_empty(state.query) { "filter off" } else { "filter \"${state.query}\"" }
	status_fg = match state.tone {
		Attached => Theme.signal
		Refused => Theme.alarm
		Rest => Theme.dim
	}
	Elem.col(Elem.ColProps.{ label: "Terminal pane", width: Fill, height: Fill, grow: True, gap: Theme.seam, fg: Theme.text, font_size: Theme.body }, [
		Elem.row(Elem.RowProps.{ label: "Session controls", width: Fill, padding: Theme.inset, gap: Theme.inset, bg: Theme.region, border_color: Theme.line, border_width: 0, border_bottom: Px(1) }, [
			key_cap("New terminal", "New terminal", !live, |current, _| start(current)),
			key_cap("Stop", "Stop terminal", live, |current, _| cancel(current)),
			Elem.row(Elem.RowProps.{ label: "Session status", padding: 4, gap: 0, grow: True, justify: End, fg: status_fg, font_size: Theme.meta }, [Elem.text(state.status)]),
		]),
		field_row("Command bar", gutter_mark(prompt_icon, "Command prompt"), Elem.text_input(Elem.TextInputProps.{ label: "Terminal command", value: state.command, placeholder: "type a command, press enter", enabled: live, on_change: |current, event| Action.update(set_command(current, event.value)), on_submit: |current, event| submit(current, event.value), grow: True, width: Fill, height: Px(26), padding: Theme.inset, font_size: Theme.body, bg: Theme.well, fg: Theme.text, border_color: Theme.edge, border_width: 1, radius: Theme.radius })),
		## The command bar and the filter bar are not peers. One sends text to a
		## child; the other only narrows what is already on screen. Making the
		## filter the header of the well it filters says which is which, and
		## puts the line count beside the control that changes it.
		Elem.col(Elem.ColProps.{ label: "Scrollback well", width: Fill, height: Fill, grow: True, gap: 0, bg: Theme.well, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip }, [
			Elem.row(Elem.RowProps.{ label: "Filter bar", width: Fill, padding: Theme.inset, gap: Theme.inset, align: Center, bg: Theme.region, border_color: Theme.line, border_width: 0, border_bottom: Px(1) }, [
				gutter_mark(search_icon, "Filter scrollback"),
				Elem.text_input(Elem.TextInputProps.{ label: "Search terminal", value: state.query, placeholder: "filter scrollback", on_change: |current, event| Action.update(set_query(current, event.value)), on_submit: |current, _| Action.update(current), grow: True, width: Fill, height: Px(22), padding: 4, font_size: Theme.meta, bg: Theme.well, fg: Theme.text, border_color: Theme.edge, border_width: 1, radius: Theme.radius }),
			]),
			if shown.len() == 0 {
				empty_well(state)
			} else {
				Elem.col(Elem.ColProps.{ label: "Scrollback rows", width: Fill, height: Fill, grow: True, padding: 4, gap: 0, font_face: Theme.face, overflow_y: Clip }, [
					Elem.virtual_list(Elem.VirtualListProps.{ label: "Terminal scrollback", row_height: Theme.row_height, items: shown }),
				])
			},
		]),
		Elem.row(Elem.RowProps.{ label: "Workspace footer", width: Fill, padding: Theme.inset, gap: 8, font_face: Theme.face, bg: Theme.region, border_color: Theme.line, border_width: 0, border_top: Px(1), fg: Theme.dim, font_size: Theme.meta }, [
			Elem.text("${shown.len().to_str()}/${state.lines.len().to_str()} lines"),
			Elem.text("|"),
			Elem.text(filtered),
			Elem.text("|"),
			Elem.text("gen ${state.generation.to_str()}"),
		]),
	])
}
