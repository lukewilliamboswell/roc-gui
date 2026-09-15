app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Gui
import pf.Program exposing [Program]

View : [Empty, Showing({ entries : List(Files.Entry), name : Str })]

Status : [Busy, Failed(Str), Ready]

Dialog : [Closed, ConfirmClose(Str)]

State : { dialog : Dialog, status : Status, view : View }

choose_directory = |state| Action.task({
	pending: { ..state, status: Busy },
	run: || match Files.pick_directory!({}) {
		Err(_) => LoadFailed("Directory access was denied")
		Ok(Canceled) => LoadCanceled
		Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
			Err(_) => LoadFailed("The granted directory could not be listed")
			Ok(entries) => Loaded({ entries, name: selection.name })
		}
	},
	resolve: |latest, result| match result {
		LoadFailed(message) => Action.update({ ..latest, status: Failed(message) })
		LoadCanceled => Action.update({ ..latest, status: Ready })
		Loaded(view) => Action.update({ ..latest, status: Ready, view: Showing(view) })
	},
})

entry_items = |entries| {
	var $key = 0
	var $items = []
	for entry in entries {
		key = $key
		kind = match entry.kind {
			Directory => "Folder"
			File => "File"
			Other => "Other"
			SymbolicLink => "Link"
		}
		$items = $items.append(Elem.VirtualListItem.{ key, content: Elem.text("Entry: ${kind}: ${entry.name}") })
		$key = key + 1
	}
	$items
}

render : State -> Elem(State)
render = |state| {
	content = match state.view {
		Empty => Elem.panel(Elem.PanelProps.{ label: "Directory content", width: Fill, grow: True }, [Elem.text("Choose a directory to begin")])
		Showing(view) => Elem.panel(
			Elem.PanelProps.{ label: "Directory content", width: Fill, height: Fill, grow: True },
			[
				Elem.row(
					Elem.RowProps.{ label: "Directory toolbar", width: Fill },
					[
						Elem.text(view.name),
						Elem.action_button(Elem.ActionButtonProps.{ caption: "Close directory", label: "Close directory", on_press: |current, _| Action.update({ ..current, dialog: ConfirmClose(view.name) }) }),
					],
				),
				Elem.virtual_list(Elem.VirtualListProps.{ name: "Directory entries", row_height: 34, items: entry_items(view.entries) }),
			],
		)
	}
	status = match state.status {
		Busy => [Elem.text("Loading…")]
		Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Directory error", border_color: Gui.rgb(0xb85c5c) }, [Elem.text(message)])]
		Ready => []
	}
	dialog = match state.dialog {
		Closed => []
		ConfirmClose(name) => [
			Elem.dialog(
				Elem.DialogProps.{ label: "Close directory confirmation", on_dismiss: |current, _| Action.update({ ..current, dialog: Closed }) },
				[
					Elem.text("Close ${name}?"),
					Elem.text("The directory grant and current view will be forgotten."),
					Elem.row(
						Elem.RowProps.{ label: "Close directory actions" },
						[
							Elem.action_button(Elem.ActionButtonProps.{ caption: "Cancel", label: "Cancel close directory", on_press: |current, _| Action.update({ ..current, dialog: Closed }) }),
							Elem.action_button(Elem.ActionButtonProps.{ caption: "Close", label: "Confirm close directory", on_press: |current, _| Action.update({ ..current, dialog: Closed, view: Empty }) }),
						],
					),
				],
			),
		]
	}
	Elem.col(
		Elem.ColProps.{ label: "File explorer", width: Fill, height: Fill, grow: True, padding: 24, gap: 16 },
		[
			Elem.text("File Explorer"),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Choose directory", label: "Choose directory", enabled: state.status != Busy, on_press: |current, _| choose_directory(current) }),
		].concat(status).append(content).concat(dialog),
	)
}

main : Program(State)
main = Program.run({
	init: { dialog: Closed, status: Ready, view: Empty },
	render,
	window: { title: "File Explorer", width: 960, height: 640 },
})
