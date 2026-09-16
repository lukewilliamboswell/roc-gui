import pf.Action
import pf.Elem
import pf.Files
import pf.Gui
import "icons/folder.svg" as folder_icon : List(U8)
import "icons/file.svg" as file_icon : List(U8)
import "icons/corner-down-right.svg" as link_icon : List(U8)

Browser := [].{
	State : State
	init : State
	init = { next_request: 1, show_files: True, status: Ready, view: Empty }
	render : State -> Elem(State)
	render = render
	## The window's own ground and ink, so `main.roc` can declare the identity
	## instead of leaving the space behind the root element to the host.
	ground : Gui.Color
	ground = ground
	ink : Gui.Color
	ink = ink
}

Location : { directory : Files.Dir.Read, name : Str }

View : [Empty, Showing({ entries : List(Files.Entry), trail : List(Location) })]

Retry : [PickAgain, OpenAgain({ name : Str, parent : Location }), ReturnAgain(U64)]

Failure : { hint : Str, message : Str, retry : Retry }

## `Dismissed` is a resting state, not a failure: the person opened the chooser
## and closed it again, which is an answer and not a fault. It is distinct from
## `Ready` only so that the first screen can acknowledge the answer instead of
## looking as though the press did nothing.
Status : [Busy(U64), Dismissed, Failed(Failure), Ready]

State : { next_request : U64, show_files : Bool, status : Status, view : View }

## Deep teal, lit from one direction: the window's ground is the darkest
## surface, panels sit one step above it, and rows one step above those. Nothing
## in the browser is brighter than the name of the folder you are looking at.
ground = Gui.rgb(0x0e1a21)
surface = Gui.rgb(0x14232b)
rule = Gui.rgb(0x2a4753)
row_bg = Gui.rgb(0x17272f)
row_hover = Gui.rgb(0x27414f)
link_fg = Gui.rgb(0x9bdcf0)
ink = Gui.rgb(0xdbe7ed)
muted_fg = Gui.rgb(0x93a7b2)
title_fg = Gui.rgb(0xf2f6f8)
chip_bg = Gui.rgb(0x203944)

## The one action that asks for authority. It is the only saturated surface in
## the window, so the press that a grant begins with is the press that looks
## like the point of the screen.
accent = Gui.rgb(0x2f6f85)
accent_hover = Gui.rgb(0x3d8aa3)
accent_active = Gui.rgb(0x265a6d)
accent_ink = Gui.rgb(0xf2fbff)

name_limit : U64
name_limit = 52

describe = |error| match error {
	PickDirectoryErr(AccessDenied) => "The directory chooser was denied"
	PickDirectoryErr(Unavailable) => "No directory chooser is available"
	PickDirectoryErr(_) => "The directory chooser failed"
	ListDirectoryErr(AccessDenied) => "This folder can no longer be read"
	ListDirectoryErr(Revoked) => "The directory grant was revoked"
	ListDirectoryErr(NotFound) => "This folder no longer exists"
	ListDirectoryErr(ResourceLimit) => "This folder holds more entries than can be listed"
	ListDirectoryErr(InvalidUtf8) => "This folder holds a name that is not valid UTF-8"
	ListDirectoryErr(_) => "This folder could not be listed"
	OpenReadDirectoryErr(NotFound) => "That folder no longer exists"
	OpenReadDirectoryErr(NotDirectory) => "That entry is no longer a folder"
	OpenReadDirectoryErr(AccessDenied) => "That folder cannot be read"
	OpenReadDirectoryErr(Revoked) => "The directory grant was revoked"
	OpenReadDirectoryErr(_) => "That folder could not be opened"
	_ => "The filesystem operation failed"
}

hint_for = |error| match error {
	PickDirectoryErr(AccessDenied) => "Grant access to a folder and try again."
	PickDirectoryErr(Unavailable) => "Start the application with a directory grant, then try again."
	ListDirectoryErr(Revoked) => "Choose a directory again to get a fresh grant."
	OpenReadDirectoryErr(Revoked) => "Choose a directory again to get a fresh grant."
	OpenReadDirectoryErr(NotFound) => "It may have been renamed or removed since this folder was listed."
	ListDirectoryErr(NotFound) => "It may have been renamed or removed since it was opened."
	_ => "Retry, or choose another directory to start again."
}

begin : State -> { id : U64, pending : State }
begin = |state| {
	id = state.next_request
	{ id, pending: { ..state, next_request: id + 1, status: Busy(id) } }
}

is_current = |state, id| match state.status {
	Busy(active) => active == id
	Dismissed => False
	Ready => False
	Failed(_) => False
}

## Shorten a name to the row's budget and mark the cut with an ellipsis.
shorten = |name| {
	bytes = Str.to_utf8(name)
	if bytes.len() <= name_limit {
		name
	} else {
		match Str.from_utf8(bytes.take_first(name_limit - 1)) {
			Ok(prefix) => "${prefix}…"
			Err(_) => name
		}
	}
}

lower_bytes = |name| Str.to_utf8(name).map(|byte| if byte >= 65 and byte <= 90 byte + 32 else byte)

## Case-insensitive name order, so `Photos` and `photos` sort together.
compare_names = |left, right| {
	left_bytes = lower_bytes(left)
	right_bytes = lower_bytes(right)
	var $result = Same
	for item in List.map2(left_bytes, right_bytes, |a, b| if a < b Before else if a > b After else Same) {
		if $result == Same {
			$result = item
		}
	}
	if $result == Same {
		if left_bytes.len() < right_bytes.len() Before else if left_bytes.len() > right_bytes.len() After else Same
	} else {
		$result
	}
}

## Folders first, then names in case-insensitive order.
ordered = |entries| List.sort_with(entries, |left, right| {
	left_dir = left.kind == Directory
	right_dir = right.kind == Directory
	if left_dir and !right_dir {
		Before
	} else if right_dir and !left_dir {
		After
	} else {
		compare_names(left.name, right.name)
	}
})

## The kind marker is drawn, not spelled: a folder, a plain file, and the
## turned arrow of a symbolic link each read at a glance in the 20pt gutter.
marker_art = |kind| match kind {
	Directory => { bytes: folder_icon, name: "Folder" }
	SymbolicLink => { bytes: link_icon, name: "Link" }
	_ => { bytes: file_icon, name: "File" }
}

start_pick = |state| {
	request = begin(state)
	Action.task({
		pending: request.pending,
		run: || match Files.pick_directory!() {
			Err(error) => PickFailed({ hint: hint_for(error), message: describe(error) })
			Ok(Canceled) => PickCanceled
			Ok(Chosen(selection)) => match selection.directory.list!() {
				Err(error) => PickFailed({ hint: hint_for(error), message: describe(error) })
				Ok(entries) => Picked({ entries, location: { directory: selection.directory, name: selection.name } })
			}
		},
		resolve: |latest, result| if !is_current(latest, request.id) {
			Action.none
		} else {
			match result {
				PickFailed(failure) => Action.update({ ..latest, status: Failed({ hint: failure.hint, message: failure.message, retry: PickAgain }) })
				## Closing the chooser is an answer. It leaves whatever was open
				## open, and only the first screen says anything about it.
				PickCanceled => Action.update({ ..latest, status: Dismissed })
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
		run: || match parent.directory.open_dir!(name) {
			Err(error) => OpenFailed({ hint: hint_for(error), message: describe(error) })
			Ok(directory) => match directory.list!() {
				Err(error) => OpenFailed({ hint: hint_for(error), message: describe(error) })
				Ok(entries) => Opened({ entries, location: { directory, name } })
			}
		},
		resolve: |latest, result| if !is_current(latest, request.id) {
			Action.none
		} else {
			match result {
				OpenFailed(failure) => Action.update({ ..latest, status: Failed({ hint: failure.hint, message: "${failure.message}: ${name}", retry: OpenAgain({ parent, name }) }) })
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
				run: || target.directory.list!(),
				resolve: |latest, result| if !is_current(latest, request.id) {
					Action.none
				} else {
					match result {
						Err(error) => Action.update({ ..latest, status: Failed({ hint: hint_for(error), message: "${describe(error)}: ${target.name}", retry: ReturnAgain(depth) }) })
						Ok(entries) => Action.update({ ..latest, status: Ready, view: Showing({ entries, trail }) })
					}
				},
			})
		}
	}
}

retry = |state, retry_value| match retry_value {
	PickAgain => start_pick(state)
	OpenAgain(value) => open_child(state, value.parent, value.name)
	ReturnAgain(depth) => go_to(state, depth)
}

## One text run in a chosen colour and size. `Elem.text` inherits both.
styled_text = |value, color, size| Elem.row(Elem.RowProps.{ fg: color, font_size: size, padding: 0, gap: 0 }, [Elem.text(value)])

## The path as a path: clickable ancestors, a separator, and the folder you are
## looking at rendered as emphasised, non-interactive text.
breadcrumbs = |trail| {
	last_index = trail.len() - 1
	var $depth = 0
	var $result = []
	for location in trail {
		current_depth = $depth
		if current_depth == last_index {
			$result = $result.append(styled_text(shorten(location.name), title_fg, 15))
		} else {
			$result = $result
				.append(Elem.action_button(Elem.ActionButtonProps.{ caption: shorten(location.name), label: "Breadcrumb ${current_depth.to_str()}", on_press: |current, _| go_to(current, current_depth), padding: 6, font_size: 13, bg: chip_bg, hover_bg: row_hover, fg: link_fg, radius: 4 }))
				.append(styled_text("›", muted_fg, 14))
		}
		$depth = current_depth + 1
	}
	$result
}

## Every entry gets the same row: marker column, then the name at one fixed x.
## A folder differs only in that its name is the control that opens it.
entry_row = |entry, current| {
	art = marker_art(entry.kind)
	marker = Elem.row(
		Elem.RowProps.{ width: Px(20), padding: 0, gap: 0 },
		[Elem.image(Elem.ImageProps.{ label: "${art.name} marker ${entry.name}", bytes: art.bytes, format: Svg, width: Px(14), height: Px(14) })],
	)
	name = if entry.kind == Directory {
		Elem.action_button(Elem.ActionButtonProps.{ caption: shorten(entry.name), label: "Open directory ${entry.name}", on_press: |current_state, _| open_child(current_state, current, entry.name), padding: 4, font_size: 14, bg: row_bg, hover_bg: row_hover, active_bg: chip_bg, fg: link_fg, radius: 4 })
	} else {
		Elem.row(Elem.RowProps.{ padding: 4, gap: 0, font_size: 14 }, [Elem.text(shorten(entry.name))])
	}
	Elem.row(Elem.RowProps.{ label: "Entry ${entry.name}", width: Fill, gap: 4, padding: 1, radius: 5, bg: row_bg, overflow_x: Clip }, [marker, name])
}

## A quiet full-width block for a state that has nothing to list.
notice = |message, detail| Elem.col(Elem.ColProps.{ label: "Directory notice", width: Fill, grow: True, padding: 24, gap: 6, align: Center, justify: Center }, [styled_text(message, Gui.rgb(0xd6e2e8), 16), styled_text(detail, muted_fg, 13)])

error_panel = |failure| Elem.panel(
	Elem.PanelProps.{ label: "Directory error", width: Fill, padding: 12, gap: 8, border_color: Gui.rgb(0xb85c5c), bg: Gui.rgb(0x2a1c1f) },
	[
		styled_text(failure.message, Gui.rgb(0xf0c9c9), 15),
		styled_text(failure.hint, muted_fg, 13),
		Elem.row(Elem.RowProps.{ label: "Directory error actions", gap: 8 }, [
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Retry", label: "Retry", padding: 6, on_press: |current, _| retry(current, failure.retry) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Choose another directory", label: "Choose another directory", padding: 6, bg: chip_bg, hover_bg: row_hover, fg: link_fg, on_press: |current, _| start_pick(current) }),
		]),
	],
)

busy_panel = Elem.panel(Elem.PanelProps.{ label: "Loading status", padding: 10, bg: chip_bg, border_color: rule, fg: muted_fg }, [Elem.text("Loading…")])

status_blocks = |status| match status {
	Busy(_) => [busy_panel]
	Failed(failure) => [error_panel(failure)]
	Dismissed => []
	Ready => []
}

counts = |entries, show_files| {
	folders = entries.keep_if(|entry| entry.kind == Directory).len()
	files = entries.len() - folders
	folder_word = if folders == 1 "1 folder" else "${folders.to_str()} folders"
	file_word = if files == 1 "1 file" else "${files.to_str()} files"
	if show_files {
		"${folder_word} · ${file_word}"
	} else {
		"${folder_word} · ${file_word} hidden"
	}
}

render : State -> Elem(State)
render = |state| {
	is_busy = match state.status {
		Busy(_) => True
		_ => False
	}
	controls = Elem.row(
		## The action that asks for authority sits at the head of the bar and the
		## filter that only changes what is already on screen sits at its far
		## end, so the two are not read as a pair of equal buttons.
		Elem.RowProps.{ label: "Directory actions", width: Fill, gap: 16, align: Center, justify: Between },
		[
			Elem.action_button(
				Elem.ActionButtonProps.{
					caption: "Choose directory",
					label: "Choose directory",
					enabled: !is_busy,
					padding: 10,
					padding_left: Px(16),
					padding_right: Px(16),
					font_size: 14,
					bg: accent,
					hover_bg: accent_hover,
					active_bg: accent_active,
					fg: accent_ink,
					radius: 7,
					on_press: |current, _| start_pick(current),
				},
			),
			Elem.checkbox(
				Elem.CheckboxProps.{
					label: "Show files as well as folders",
					checked: state.show_files,
					on_change: |current, event| Action.update({ ..current, show_files: event.checked }),
					padding: 10,
					font_size: 14,
					bg: chip_bg,
					hover_bg: row_hover,
					fg: ink,
					border_color: rule,
					border_width: 1,
					radius: 7,
				},
			),
		],
	)
	content = match state.view {
		Empty => Elem.panel(
			Elem.PanelProps.{ label: "Directory content", width: Fill, grow: True, gap: 12, bg: surface, border_color: rule, overflow_y: Clip },
			match state.status {
				Failed(failure) => [error_panel(failure)]
				Busy(_) => [busy_panel]
				## A closed chooser is answered, not ignored. Saying so is the
				## difference between a press that did nothing and a press
				## whose answer was "not now".
				Dismissed => [notice("No folder chosen", "The chooser was closed. Choose a directory whenever you are ready.")]
				Ready => [notice("No folder open", "This browser reads only the folders you hand it. Choose a directory to begin.")]
			},
		)
		Showing(view) => {
			current = view.trail.last() ?? crash "showing view has a location"
			back = if view.trail.len() > 1 {
				[Elem.action_button(Elem.ActionButtonProps.{ caption: "‹ Back", label: "Back", on_press: |current_state, _| go_to(current_state, view.trail.len() - 2), padding: 6, font_size: 13, bg: chip_bg, hover_bg: row_hover, fg: link_fg, radius: 4 })]
			} else {
				[]
			}
			shown = ordered(view.entries.keep_if(|entry| state.show_files or entry.kind == Directory))
			body = if shown.is_empty() {
				if view.entries.is_empty() {
					notice("This folder is empty", "Nothing is stored in ${current.name}.")
				} else {
					notice("No folders here", "${current.name} holds only files. Tick “Show files as well as folders” to see them.")
				}
			} else {
				Elem.scroll(Elem.ScrollProps.{ label: "Directory contents", content: Elem.col(Elem.ColProps.{ label: "Directory entries", width: Fill, gap: 2 }, shown.map(|entry| entry_row(entry, current))) })
			}
			Elem.panel(
				Elem.PanelProps.{ label: "Directory view", width: Fill, grow: True, gap: 8, bg: surface, border_color: rule, overflow_y: Clip },
				[
					Elem.row(Elem.RowProps.{ label: "Directory breadcrumbs", width: Fill, gap: 6 }, back.concat(breadcrumbs(view.trail))),
					styled_text(counts(view.entries, state.show_files), muted_fg, 13),
				]
					.concat(status_blocks(state.status))
					.append(body),
			)
		}
	}
	Elem.col(
		Elem.ColProps.{ label: "Folder browser", width: Fill, height: Fill, grow: True, padding: 20, gap: 14, overflow_y: Clip },
		[
			## The subtitle states the bargain the application is made of. It is
			## the one thing a person needs to know before the first press, and
			## it stops being worth saying once a folder is on screen.
			Elem.col(
				Elem.ColProps.{ label: "Folder browser heading", gap: 4 },
				[
					styled_text("Folder browser", title_fg, 22),
					styled_text("Read only the folders you hand it, one at a time", muted_fg, 13),
				],
			),
			Elem.panel(Elem.PanelProps.{ label: "Directory controls", width: Fill, padding: 12, bg: surface, border_color: rule }, [controls]),
			content,
		],
	)
}
