app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Gui
import pf.Layout
import pf.Program exposing [Program]

State : [Idle({ show_files : Bool }), Loading({ show_files : Bool }), Loaded({ name : Str, entries : List(Files.Entry), show_files : Bool }), Failed(Str)]

start_pick : State -> Action.Action(State)
start_pick = |state| {
	show_files = match state { Idle(value) => value.show_files, Loading(value) => value.show_files, Loaded(value) => value.show_files, Failed(_) => True }
	Action.task({
	pending: Loading({ show_files: show_files }),
	run: || Files.pick_directory!({}),
	resolve: |latest, result| match result {
		Err(_) => Action.update(Failed("Directory access was denied"))
		Ok(Canceled) => Action.update(Idle({ show_files: True }))
		Ok(Chosen(selection)) => Action.task({
			pending: Loading({ show_files: show_files }),
			run: || Files.Dir.list!(selection.directory),
			resolve: |_, listed| match listed {
				Err(_) => Action.update(Failed("Could not list the directory"))
				Ok(entries) => Action.update(Loaded({ name: selection.name, entries, show_files: match latest { Loading(value) => value.show_files, Idle(value) => value.show_files, Loaded(value) => value.show_files, Failed(_) => show_files } }))
			},
			})
		},
	})
}

render : State -> Elem(State)
render = |state| {
	header = Elem.text("Capability folder browser")
	body = match state {
		Idle(options) => Layout.col({}, [
			Elem.checkbox(Elem.CheckboxProps.{
				label: "Show files as well as folders",
				checked: options.show_files,
				on_change: |_, event| Action.update(Idle({ show_files: event.checked })),
				padding: 8,
				bg: Gui.rgb(0x203944),
				hover_bg: Gui.rgb(0x294a58),
				fg: Gui.rgb(0xeeeeea),
				border_color: Gui.rgb(0x79b8ca),
				border_width: 1,
				radius: 6,
			}),
			Elem.button({ label: Elem.text("Choose directory"), name: "Choose directory", on_press: |current, _| start_pick(current) }),
		])
		Loading(_) => Elem.text("Loading…")
		Failed(message) => Layout.col({}, [Elem.text(message), Elem.button({ label: Elem.text("Try again"), name: "Try again", on_press: |current, _| start_pick(current) })])
		Loaded(data) => Layout.col({}, [Elem.text(data.name)].concat(
			data.entries.keep_if(|entry| if data.show_files { True } else { entry.kind == Directory }).map(|entry| Elem.text(entry.name)),
		))
	}
	Layout.col({}, [header, body])
}

main : Program(State)
main = Program.run({ init: Idle({ show_files: True }), render })
