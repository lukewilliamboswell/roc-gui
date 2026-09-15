import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Gui

Explorer := [].{
	State : State
	init : State
	init = { back: [], dialog: Closed, forward: [], root: None, selection: NoneSelected, status: Ready, view: Empty }
	render : State -> Elem(State)
	render = render
}

Folder : { directory : Files.Dir.Read, entries : List(Files.Entry), name : Str, trail : List(Str) }
View : [Empty, Showing(Folder)]
Selection : [NoneSelected, Selected(Files.Entry)]
Status : [Busy, Failed(Str), Ready]
Dialog : [Closed, ConfirmClose(Str)]
State : { back : List(Folder), dialog : Dialog, forward : List(Folder), root : [None, Some(Folder)], selection : Selection, status : Status, view : View }

describe = |error| match error {
	PickDirectoryErr(AccessDenied) => "Directory access was denied"
	PickDirectoryErr(_) => "The directory chooser failed"
	ListDirectoryErr(AccessDenied) => "The directory can no longer be read"
	ListDirectoryErr(Revoked) => "The directory grant was revoked"
	ListDirectoryErr(ResourceLimit) => "The directory contains too many entries"
	ListDirectoryErr(InvalidUtf8) => "The directory contains a name that is not valid UTF-8"
	ListDirectoryErr(_) => "The directory could not be listed"
	OpenReadDirectoryErr(NotFound) => "The selected folder no longer exists"
	OpenReadDirectoryErr(NotDirectory) => "The selected entry is no longer a folder"
	OpenReadDirectoryErr(AccessDenied) => "The selected folder cannot be read"
	OpenReadDirectoryErr(Revoked) => "The directory grant was revoked"
	ReadFileErr(Revoked) => "The directory grant was revoked"
	OpenReadDirectoryErr(_) => "The selected folder could not be opened"
	_ => "The filesystem operation failed"
}

refresh = |state, folder| Action.task({ pending: { ..state, status: Busy }, run: || Files.Dir.list!(folder.directory), resolve: |latest, result| match result { Err(error) => Action.update({ ..latest, status: Failed(describe(error)) }), Ok(entries) => Action.update({ ..latest, status: Ready, view: Showing({ ..folder, entries }) }) } })

read_file = |state, folder, name| Action.task({ pending: { ..state, status: Busy }, run: || Files.Dir.read!(folder.directory, name), resolve: |latest, result| match result { Err(error) => Action.update({ ..latest, status: Failed(describe(error)) }), Ok(_) => Action.update({ ..latest, status: Ready }) } })

choose_directory = |state| Action.task({
	pending: { ..state, status: Busy },
	run: || match Files.pick_directory!() {
		Err(error) => LoadFailed(describe(error))
		Ok(Canceled) => LoadCanceled
		Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
			Err(error) => LoadFailed(describe(error))
			Ok(entries) => Loaded({ directory: selection.directory, entries, name: selection.name, trail: [selection.name] })
		}
	},
	resolve: |latest, result| match result {
		LoadFailed(message) => Action.update({ ..latest, status: Failed(message) })
		LoadCanceled => Action.update({ ..latest, status: Ready })
		Loaded(folder) => Action.update({ ..latest, back: [], forward: [], root: Some(folder), selection: NoneSelected, status: Ready, view: Showing(folder) })
	},
})

open_folder = |state, current, name| Action.task({
	pending: { ..state, status: Busy },
	run: || match Files.Dir.open_read_dir!(current.directory, name) {
		Err(error) => LoadFailed(describe(error))
		Ok(directory) => match Files.Dir.list!(directory) {
			Err(error) => LoadFailed(describe(error))
			Ok(entries) => Loaded({ directory, entries, name, trail: current.trail.append(name) })
		}
	},
	resolve: |latest, result| match result {
		LoadFailed(message) => Action.update({ ..latest, status: Failed(message) })
		LoadCanceled => Action.update({ ..latest, status: Ready })
		Loaded(folder) => Action.update({ ..latest, back: latest.back.append(current), forward: [], selection: NoneSelected, status: Ready, view: Showing(folder) })
	},
})

go_back = |state, current| match state.back.last() {
	Err(_) => Action.none
	Ok(previous) => Action.update({ ..state, back: state.back.drop_last(1), forward: state.forward.append(current), selection: NoneSelected, view: Showing(previous) })
}

go_forward = |state, current| match state.forward.last() {
	Err(_) => Action.none
	Ok(next) => Action.update({ ..state, back: state.back.append(current), forward: state.forward.drop_last(1), selection: NoneSelected, view: Showing(next) })
}

go_root = |state, current| match state.root {
	None => Action.none
	Some(root) => if root.trail == current.trail Action.none else Action.update({ ..state, back: state.back.append(current), forward: [], selection: NoneSelected, view: Showing(root) })
}

entry_items = |folder| folder.entries.map_with_index(|entry, key| {
	kind = match entry.kind { Directory => "Folder", File => "File", Other => "Other", SymbolicLink => "Link" }
	label = "${kind}: ${entry.name}"
	select = Elem.action_button(Elem.ActionButtonProps.{ caption: "Entry: ${label}", label: "Select ${label}", on_press: |current, _| Action.update({ ..current, selection: Selected(entry), status: Ready }) })
	content = if entry.kind == Directory {
		Elem.row(Elem.RowProps.{ label: "Folder entry ${entry.name}" }, [select, Elem.action_button(Elem.ActionButtonProps.{ caption: "Open", label: "Open folder ${entry.name}", on_press: |current, _| open_folder(current, folder, entry.name) })])
	} else if entry.kind == File {
		Elem.row(Elem.RowProps.{ label: "File entry ${entry.name}" }, [select, Elem.action_button(Elem.ActionButtonProps.{ caption: "Read", label: "Read file ${entry.name}", on_press: |current, _| read_file(current, folder, entry.name) })])
	} else select
	Elem.VirtualListItem.{ key, content }
})

render : State -> Elem(State)
render = |state| {
	content = match state.view {
		Empty => Elem.panel(Elem.PanelProps.{ label: "Directory content", width: Fill, grow: True }, [Elem.text("Open a project to begin")])
		Showing(folder) => Elem.panel(Elem.PanelProps.{ label: "Directory content", width: Fill, height: Fill, grow: True }, [
			Elem.row(Elem.RowProps.{ label: "Directory toolbar", width: Fill }, [
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Back", label: "Back", enabled: !state.back.is_empty(), on_press: |current, _| go_back(current, folder) }),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Forward", label: "Forward", enabled: !state.forward.is_empty(), on_press: |current, _| go_forward(current, folder) }),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Root", label: "Breadcrumb root", on_press: |current, _| go_root(current, folder) }),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Refresh", label: "Refresh directory", on_press: |current, _| refresh(current, folder) }),
				Elem.text(Str.join_with(folder.trail, " / ")),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Close directory", label: "Close directory", on_press: |current, _| Action.update({ ..current, dialog: ConfirmClose(folder.name) }) }),
			]),
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Directory entries", row_height: 34, items: entry_items(folder) }),
		])
	}
	selection = match state.selection { NoneSelected => [], Selected(entry) => [Elem.panel(Elem.PanelProps.{ label: "Selection details", width: Fill }, [Elem.text("Selected: ${entry.name}"), Elem.text(match entry.bytes { None => "Size unavailable", Some(bytes) => "Size: ${bytes.to_str()} bytes" })])] }
	status = match state.status { Busy => [Elem.text("Loading…")], Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Directory error", border_color: Gui.rgb(0xb85c5c) }, [Elem.text(message)])], Ready => [] }
	dialog = match state.dialog {
		Closed => []
		ConfirmClose(name) => [Elem.dialog(Elem.DialogProps.{ label: "Close directory confirmation", on_dismiss: |current, _| Action.update({ ..current, dialog: Closed }) }, [Elem.text("Close ${name}?"), Elem.text("The directory grant and current view will be forgotten."), Elem.row(Elem.RowProps.{ label: "Close directory actions" }, [Elem.action_button(Elem.ActionButtonProps.{ caption: "Cancel", label: "Cancel close directory", on_press: |current, _| Action.update({ ..current, dialog: Closed }) }), Elem.action_button(Elem.ActionButtonProps.{ caption: "Close", label: "Confirm close directory", on_press: |current, _| Action.update({ ..current, back: [], dialog: Closed, forward: [], root: None, selection: NoneSelected, view: Empty }) })])])]
	}
	Elem.col(Elem.ColProps.{ label: "File explorer", width: Fill, height: Fill, grow: True, padding: 24, gap: 16 }, [Elem.text("File Explorer"), Elem.action_button(Elem.ActionButtonProps.{ caption: "Open project", label: "Open project", enabled: state.status != Busy, on_press: |current, _| choose_directory(current) })].concat(status).append(content).concat(selection).concat(dialog))
}
