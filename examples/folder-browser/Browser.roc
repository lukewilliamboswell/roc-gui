import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Gui

Browser := [].{
	State : State
	init : State
	init = { next_request: 1, show_files: True, status: Ready, view: Empty }
	render : State -> Elem(State)
	render = render
}

Location : { directory : Files.Dir.Read, name : Str }

View : [Empty, Showing({ entries : List(Files.Entry), trail : List(Location) })]

Retry : [PickAgain, OpenAgain({ name : Str, parent : Location }), ReturnAgain(U64)]

Status : [Busy(U64), Failed({ message : Str, retry : Retry }), Ready]

State : { next_request : U64, show_files : Bool, status : Status, view : View }

begin = |state| {
	id = state.next_request
	{ id, pending: { ..state, next_request: id + 1, status: Busy(id) } }
}

is_current = |state, id| match state.status {
	Busy(active) => active == id
	Ready => False
	Failed(_) => False
}

start_pick = |state| {
	request = begin(state)
	Action.task({
		pending: request.pending,
		run: || match Files.pick_directory!({}) {
			Err(_) => PickFailed
			Ok(Canceled) => PickCanceled
			Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
				Err(_) => PickFailed
				Ok(entries) => Picked({ entries, location: { directory: selection.directory, name: selection.name } })
			}
		},
		resolve: |latest, result| if !is_current(latest, request.id) {
			Action.none
		} else {
			match result {
				PickFailed => Action.update({ ..latest, status: Failed({ message: "Could not open the granted directory", retry: PickAgain }) })
				PickCanceled => Action.update({ ..latest, status: Ready })
				Picked(value) => Action.update({ ..latest, status: Ready, view: Showing({ entries: value.entries, trail: [value.location] }) })
			}
		},
	})
}

open_child = |state, parent, name| {
	request = begin(state)
	previous_trail = match state.view {
		Showing(value) => value.trail
		Empty => []
	}
	Action.task({
		pending: request.pending,
		run: || match Files.Dir.open_read_dir!(parent.directory, name) {
			Err(_) => OpenFailed
			Ok(directory) => match Files.Dir.list!(directory) {
				Err(_) => OpenFailed
				Ok(entries) => Opened({ entries, location: { directory, name } })
			}
		},
		resolve: |latest, result| if !is_current(latest, request.id) {
			Action.none
		} else {
			match result {
				OpenFailed => Action.update({ ..latest, status: Failed({ message: "Could not open ${name}", retry: OpenAgain({ parent, name }) }) })
				Opened(value) => Action.update({ ..latest, status: Ready, view: Showing({ entries: value.entries, trail: previous_trail.append(value.location) }) })
			}
		},
	})
}

go_to = |state, depth| match state.view {
	Empty => Action.none
	Showing(view) => {
		trail = view.trail.take_first(depth + 1)
		if trail.len() == view.trail.len() {
			Action.none
		} else {
			target = trail.last() ?? crash "non-empty breadcrumb trail"
			request = begin(state)
			Action.task({
				pending: request.pending,
				run: || Files.Dir.list!(target.directory),
				resolve: |latest, result| if !is_current(latest, request.id) {
					Action.none
				} else {
					match result {
						Err(_) => Action.update({ ..latest, status: Failed({ message: "Could not return to ${target.name}", retry: ReturnAgain(depth) }) })
						Ok(entries) => Action.update({ ..latest, status: Ready, view: Showing({ entries, trail }) })
					}
				},
			})
		}
	}
}

breadcrumbs = |trail| {
	var $depth = 0
	var $result = []
	for location in trail {
		current_depth = $depth
		$result = $result.append(Elem.action_button(Elem.ActionButtonProps.{ caption: location.name, label: "Breadcrumb ${current_depth.to_str()}", on_press: |current, _| go_to(current, current_depth), padding: 6, bg: Gui.rgb(0x203944) }))
		$depth = current_depth + 1
	}
	$result
}

retry = |state, retry_value| match retry_value {
	PickAgain => start_pick(state)
	OpenAgain(value) => open_child(state, value.parent, value.name)
	ReturnAgain(depth) => go_to(state, depth)
}

render : State -> Elem(State)
render = |state| {
	is_busy = match state.status {
		Busy(_) => True
		_ => False
	}
	controls = [
		Elem.checkbox(
			Elem.CheckboxProps.{
				label: "Show files as well as folders",
				checked: state.show_files,
				on_change: |current, event| Action.update({ ..current, show_files: event.checked }),
				padding: 8,
				bg: Gui.rgb(0x203944),
				hover_bg: Gui.rgb(0x294a58),
				fg: Gui.rgb(0xeeeeea),
				border_color: Gui.rgb(0x79b8ca),
				border_width: 1,
				radius: 6,
			},
		),
		Elem.action_button(Elem.ActionButtonProps.{ caption: "Choose directory", label: "Choose directory", enabled: !is_busy, on_press: |current, _| start_pick(current), width: Fill, fg: Gui.rgb(0xeeeeea) }),
	]
	status = match state.status {
		Busy(_) => [Elem.panel(Elem.PanelProps.{ label: "Loading status", width: Fill, padding: 12 }, [Elem.text("Loading…")])]
		Failed(failure) => [Elem.panel(Elem.PanelProps.{ label: "Directory error", width: Fill, padding: 12, border_color: Gui.rgb(0xb85c5c) }, [Elem.text(failure.message), Elem.action_button(Elem.ActionButtonProps.{ caption: "Retry", label: "Retry", on_press: |current, _| retry(current, failure.retry) })])]
		Ready => []
	}
	content = match state.view {
		Empty => Elem.panel(Elem.PanelProps.{ label: "Directory content", width: Fill, grow: True }, [Elem.text("Choose a directory to begin")])
		Showing(view) => {
			current = view.trail.last() ?? crash "showing view has a location"
			back = if view.trail.len() > 1 {
				[Elem.action_button(Elem.ActionButtonProps.{ caption: "Back", label: "Back", on_press: |current_state, _| go_to(current_state, view.trail.len() - 2), padding: 6 })]
			} else {
				[]
			}
			rows = view.entries.keep_if(|entry| state.show_files or entry.kind == Directory).map(
				|entry| if entry.kind == Directory {
					Elem.action_button(Elem.ActionButtonProps.{ caption: "Folder: ${entry.name}", label: "Open directory ${entry.name}", on_press: |current_state, _| open_child(current_state, current, entry.name), width: Fill, fg: Gui.rgb(0xeeeeea) })
				} else {
					Elem.text("File: ${entry.name}")
				},
			)
			Elem.panel(
				Elem.PanelProps.{ label: "Directory view", width: Fill, height: Fill, grow: True, gap: 12 },
				back.concat([
					Elem.row(Elem.RowProps.{ label: "Directory breadcrumbs", width: Fill, gap: 6 }, breadcrumbs(view.trail)),
					Elem.scroll(Elem.ScrollProps.{ name: "Directory contents", content: Elem.col(Elem.ColProps.{ label: "Directory entries", width: Fill, gap: 6 }, rows) }),
				]),
			)
		}
	}
	Elem.col(
		Elem.ColProps.{ label: "Folder browser", width: Fill, height: Fill, grow: True, padding: 24, gap: 16 },
		[
			Elem.text("Capability folder browser"),
			Elem.panel(Elem.PanelProps.{ label: "Directory controls", width: Fill, gap: 12 }, controls),
		].concat(status).append(content),
	)
}
