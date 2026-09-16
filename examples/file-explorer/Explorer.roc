import pf.Action
import pf.Elem
import pf.Files
import pf.Gui
import "icons/folder.svg" as folder_icon : List(U8)
import "icons/file.svg" as file_icon : List(U8)
import "icons/corner-down-right.svg" as link_icon : List(U8)

Explorer := [].{
	State : State
	init : State
	init = { back: [], dialog: Closed, forward: [], read: Unread, root: None, selection: NoneSelected, status: Ready, view: Empty }
	render : State -> Elem(State)
	render = render
	## The window's own ground and ink. The explorer mixes every surface it
	## paints against these, so it declares them rather than borrowing whatever
	## ground the host happens to use.
	ground : Gui.Color
	ground = ground
	ink : Gui.Color
	ink = ink
}

Folder : { directory : Files.Dir.Read, entries : List(Files.Entry), name : Str, trail : List(Str) }
View : [Empty, Showing(Folder)]
Selection : [NoneSelected, Selected(Files.Entry)]

## What a failure needs in order to be acted on: what happened, and what the
## person can do about it. A message without a next step is an apology.
Failure : { hint : Str, message : Str }

## `Dismissed` is rest, not failure. Someone opened the chooser and closed it
## again, which is an answer; the platform reports it as success and the
## application must not dress it as a refusal.
Status : [Busy, Dismissed, Failed(Failure), Ready]

## The evidence that a read actually happened. A "Read" control whose success
## looks exactly like its own idle state is a control that cannot be trusted.
Read : [Unread, ReadOf({ bytes : U64, name : Str, preview : Str })]

Dialog : [Closed, ConfirmClose(Str)]
State : { back : List(Folder), dialog : Dialog, forward : List(Folder), read : Read, root : [None, Some(Folder)], selection : Selection, status : Status, view : View }

## Graphite and amber. The ground is the darkest surface, the chrome sits one
## step above it, and a raised row one step above that. Amber is spent on
## exactly two things: the project grant, and the entry you have selected.
ground = Gui.rgb(0x14161a)
surface = Gui.rgb(0x1c1f25)
raised = Gui.rgb(0x252931)
rule = Gui.rgb(0x31363f)
ink = Gui.rgb(0xe6e8ec)
muted = Gui.rgb(0x959ba6)
dim = Gui.rgb(0x757b86)

accent = Gui.rgb(0xd8a13f)
accent_hover = Gui.rgb(0xe6b357)
accent_active = Gui.rgb(0xba8830)
accent_ink = Gui.rgb(0x1a1408)

danger_bg = Gui.rgb(0x2a1b18)
danger_edge = Gui.rgb(0xa85b4e)
danger_ink = Gui.rgb(0xf1cec6)
danger_button = Gui.rgb(0x6d342c)
danger_button_hover = Gui.rgb(0x87423a)

preview_limit : U64
preview_limit = 96

describe = |error| match error {
	PickDirectoryErr(AccessDenied) => "Directory access was denied"
	PickDirectoryErr(Unavailable) => "No project chooser is available"
	PickDirectoryErr(_) => "The directory chooser failed"
	ListDirectoryErr(AccessDenied) => "The directory can no longer be read"
	ListDirectoryErr(Revoked) => "The directory grant was revoked"
	ListDirectoryErr(NotFound) => "The directory no longer exists"
	ListDirectoryErr(ResourceLimit) => "The directory contains too many entries"
	ListDirectoryErr(InvalidUtf8) => "The directory contains a name that is not valid UTF-8"
	ListDirectoryErr(_) => "The directory could not be listed"
	OpenReadDirectoryErr(NotFound) => "The selected folder no longer exists"
	OpenReadDirectoryErr(NotDirectory) => "The selected entry is no longer a folder"
	OpenReadDirectoryErr(AccessDenied) => "The selected folder cannot be read"
	OpenReadDirectoryErr(Revoked) => "The directory grant was revoked"
	ReadFileErr(Revoked) => "The directory grant was revoked"
	ReadFileErr(NotFound) => "That file no longer exists"
	ReadFileErr(ResourceLimit) => "That file is too large to read in one piece"
	ReadFileErr(_) => "That file could not be read"
	OpenReadDirectoryErr(_) => "The selected folder could not be opened"
	_ => "The filesystem operation failed"
}

## Every failure says what to do next, and the sentence is specific to the
## authority that failed. A revoked grant is not retried, it is re-asked for.
hint_for = |error| match error {
	PickDirectoryErr(AccessDenied) => "Open a project to grant this window one folder. Nothing outside it can be reached."
	PickDirectoryErr(Unavailable) => "Start the application with a project grant, then open it again."
	ListDirectoryErr(Revoked) => "The grant this window held has ended. Open a project again to get a fresh one."
	OpenReadDirectoryErr(Revoked) => "The grant this window held has ended. Open a project again to get a fresh one."
	ReadFileErr(Revoked) => "The grant this window held has ended. Open a project again to get a fresh one."
	OpenReadDirectoryErr(NotFound) => "It may have been renamed or removed since this folder was listed. Refresh to see what is there now."
	ListDirectoryErr(NotFound) => "It may have been renamed or removed since it was opened. Open a project again to start over."
	ReadFileErr(NotFound) => "It may have been renamed or removed since this folder was listed. Refresh to see what is there now."
	_ => "Refresh the folder, or open a project again to start over."
}

fail = |error| Failed({ hint: hint_for(error), message: describe(error) })

## A first line of the file's own bytes, when they are text. Reading is the one
## operation whose result is invisible unless the application shows it, and a
## byte count alone does not prove the bytes were the file's.
preview_of = |bytes| {
	head = bytes.take_first(preview_limit)
	match Str.from_utf8(head) {
		Err(_) => ""
		Ok(value) => {
			var $line = []
			var $done = False
			for byte in Str.to_utf8(value) {
				if !$done {
					if byte == 10 or byte == 13 {
						$done = True
					} else {
						$line = $line.append(byte)
					}
				}
			}
			match Str.from_utf8($line) {
				Ok(line) => line
				Err(_) => ""
			}
		}
	}
}

refresh = |state, folder| Action.task({
	pending: { ..state, status: Busy },
	run: || Files.Dir.list!(folder.directory),
	resolve: |latest, result| match result {
		Err(error) => Action.update({ ..latest, status: fail(error) })
		Ok(entries) => Action.update({ ..latest, status: Ready, view: Showing({ ..folder, entries }) })
	},
})

read_file = |state, folder, name| Action.task({
	pending: { ..state, read: Unread, status: Busy },
	run: || Files.Dir.read!(folder.directory, name),
	resolve: |latest, result| match result {
		Err(error) => Action.update({ ..latest, status: fail(error) })
		Ok(bytes) => Action.update({ ..latest, read: ReadOf({ bytes: bytes.len(), name, preview: preview_of(bytes) }), status: Ready })
	},
})

choose_directory = |state| Action.task({
	pending: { ..state, status: Busy },
	run: || match Files.pick_directory!() {
		Err(error) => LoadFailed({ hint: hint_for(error), message: describe(error) })
		Ok(Canceled) => LoadCanceled
		Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
			Err(error) => LoadFailed({ hint: hint_for(error), message: describe(error) })
			Ok(entries) => Loaded({ directory: selection.directory, entries, name: selection.name, trail: [selection.name] })
		}
	},
	resolve: |latest, result| match result {
		LoadFailed(failure) => Action.update({ ..latest, status: Failed(failure) })
		## Closing the chooser leaves whatever was open exactly as it was.
		LoadCanceled => Action.update({ ..latest, status: Dismissed })
		Loaded(folder) => Action.update({ ..latest, back: [], forward: [], read: Unread, root: Some(folder), selection: NoneSelected, status: Ready, view: Showing(folder) })
	},
})

open_folder = |state, current, name| Action.task({
	pending: { ..state, status: Busy },
	run: || match Files.Dir.open_read_dir!(current.directory, name) {
		Err(error) => LoadFailed({ hint: hint_for(error), message: describe(error) })
		Ok(directory) => match Files.Dir.list!(directory) {
			Err(error) => LoadFailed({ hint: hint_for(error), message: describe(error) })
			Ok(entries) => Loaded({ directory, entries, name, trail: current.trail.append(name) })
		}
	},
	resolve: |latest, result| match result {
		LoadFailed(failure) => Action.update({ ..latest, status: Failed(failure) })
		LoadCanceled => Action.update({ ..latest, status: Dismissed })
		Loaded(folder) => Action.update({ ..latest, back: latest.back.append(current), forward: [], read: Unread, selection: NoneSelected, status: Ready, view: Showing(folder) })
	},
})

go_back = |state, current| match state.back.last() {
	Err(_) => Action.none
	Ok(previous) => Action.update({ ..state, back: state.back.drop_last(1), forward: state.forward.append(current), read: Unread, selection: NoneSelected, view: Showing(previous) })
}

go_forward = |state, current| match state.forward.last() {
	Err(_) => Action.none
	Ok(next) => Action.update({ ..state, back: state.back.append(current), forward: state.forward.drop_last(1), read: Unread, selection: NoneSelected, view: Showing(next) })
}

go_root = |state, current| match state.root {
	None => Action.none
	Some(root) => if root.trail == current.trail Action.none else Action.update({ ..state, back: state.back.append(current), forward: [], read: Unread, selection: NoneSelected, view: Showing(root) })
}

## One text run in a chosen colour and size. `Elem.text` inherits both.
styled_text = |value, color, size| Elem.row(Elem.RowProps.{ fg: color, font_size: size, padding: 0, gap: 0 }, [Elem.text(value)])

kind_name = |kind| match kind {
	Directory => "Folder"
	File => "File"
	Other => "Other"
	SymbolicLink => "Link"
}

## The kind of an entry is drawn, never spelled, so a listing can be scanned by
## shape before any of its names are read. Every kind gets a glyph, including
## the ones the toolbar has no action for: a row without a marker would read as
## a rendering failure rather than as an unusual entry.
kind_art = |kind| match kind {
	Directory => folder_icon
	SymbolicLink => link_icon
	Other => link_icon
	File => file_icon
}

kind_mark = |kind, name| Elem.row(
	Elem.RowProps.{ width: Px(30), padding: 0, gap: 0, justify: Center, align: Center },
	[Elem.image(Elem.ImageProps.{ label: "${kind_name(kind)} marker ${name}", bytes: kind_art(kind), format: Svg, width: Px(15), height: Px(15) })],
)

## A file's size at a glance, in the largest unit that keeps it short. The
## exact byte count belongs in the selection panel; a column of them would be
## a column of noise to scan past.
compact_size = |bytes| if bytes < 1000.U64 {
	"${bytes.to_str()} B"
} else if bytes < 1000000.U64 {
	"${(bytes / 1000.U64).to_str()} kB"
} else if bytes < 1000000000.U64 {
	"${(bytes / 1000000.U64).to_str()} MB"
} else {
	"${(bytes / 1000000000.U64).to_str()} GB"
}

## The size column. It is what fills the distance between a short name and the
## row's action, and it is the column a person actually scans, so it is set in
## the fixed-pitch face and aligned on its right edge where the digits line up.
size_cell = |entry| Elem.row(
	Elem.RowProps.{
		width: Px(96),
		padding: 0,
		gap: 0,
		justify: End,
		fg: dim,
		font_size: 12,
		font_face: Monospace,
		text_overflow: Ellipsis,
		overflow_x: Clip,
	},
	[
		Elem.text(
			match entry.bytes {
				None => "—"
				Some(bytes) => compact_size(bytes)
			},
		),
	],
)

## A trailing control on a row. It is quiet by default and only lifts under the
## pointer: a list whose every row shouts has no emphasis left for the row you
## are actually on.
row_action = |caption, label, on_press| Elem.action_button(
	Elem.ActionButtonProps.{
		caption,
		label,
		on_press,
		width: Px(64),
		padding: 5,
		font_size: 13,
		bg: surface,
		hover_bg: raised,
		active_bg: rule,
		fg: muted,
		border_color: rule,
		border_width: 1,
		radius: 5,
		focus_color: accent,
	},
)

## Every entry gets the same row: a marker gutter, the name at one fixed x, and
## whatever the entry's kind can be asked to do at the far end. Selecting is
## pressing the name, so the row's largest target is its most ordinary action.
entry_row = |folder, entry, selected| {
	label = "${kind_name(entry.kind)}: ${entry.name}"
	row_bg = if selected raised else surface
	name = Elem.action_button(
		Elem.ActionButtonProps.{
			caption: entry.name,
			label: "Select ${label}",
			on_press: |current, _| Action.update({ ..current, read: Unread, selection: Selected(entry), status: Ready }),
			width: Fill,
			grow: True,
			justify: Start,
			padding: 5,
			font_size: 14,
			bg: row_bg,
			hover_bg: raised,
			active_bg: rule,
			fg: if selected accent else ink,
			radius: 5,
			focus_color: accent,
			text_overflow: Ellipsis,
			overflow_x: Clip,
		},
	)
	trailing = match entry.kind {
		Directory => [row_action("Open", "Open folder ${entry.name}", |current, _| open_folder(current, folder, entry.name))]
		File => [row_action("Read", "Read file ${entry.name}", |current, _| read_file(current, folder, entry.name))]
		_ => []
	}
	Elem.row(
		Elem.RowProps.{
			label: "${kind_name(entry.kind)} entry ${entry.name}",
			width: Fill,
			height: Px(30),
			gap: 6,
			padding: 0,
			padding_right: Px(6),
			align: Center,
			bg: row_bg,
			## The whole row lifts under the pointer, not just the name. A
			## highlight that stops where one child ends reads as a bar drawn
			## across the row rather than as the row responding.
			hover_bg: raised,
			radius: 6,
			overflow_x: Clip,
		},
		[kind_mark(entry.kind, entry.name), name, size_cell(entry)].concat(trailing),
	)
}

entry_items = |state, folder| {
	selected_name = match state.selection {
		NoneSelected => ""
		Selected(entry) => entry.name
	}
	folder.entries.map_with_index(|entry, key| Elem.VirtualListItem.{ key, content: entry_row(folder, entry, entry.name == selected_name) })
}

toolbar_button = |caption, label, enabled, on_press| Elem.action_button(
	Elem.ActionButtonProps.{
		caption,
		label,
		enabled,
		on_press,
		padding: 6,
		padding_left: Px(11),
		padding_right: Px(11),
		font_size: 13,
		bg: raised,
		hover_bg: rule,
		active_bg: surface,
		fg: ink,
		disabled_bg: surface,
		disabled_fg: dim,
		border_color: rule,
		border_width: 1,
		radius: 6,
		focus_color: accent,
	},
)

## The path as a path. The root is a control because it is somewhere you can
## go; the segments after it are text because, in this read-authority slice,
## they are somewhere you can only be.
path_strip = |folder| {
	last_index = folder.trail.len() - 1
	var $depth = 0
	var $result = []
	for segment in folder.trail {
		current_depth = $depth
		if current_depth > 0 {
			$result = $result.append(styled_text("›", dim, 13))
		}
		if current_depth == last_index {
			$result = $result.append(styled_text(segment, ink, 14))
		} else {
			$result = $result.append(styled_text(segment, muted, 14))
		}
		$depth = current_depth + 1
	}
	$result
}

busy_chip = Elem.row(
	Elem.RowProps.{ label: "Loading status", padding: 6, padding_left: Px(10), padding_right: Px(10), gap: 0, bg: raised, fg: muted, font_size: 13, radius: 6 },
	[Elem.text("Loading…")],
)

## A refusal is a state you act from, not a string dropped on the floor. It
## names what happened, what it means for what you can reach, and offers the
## one press that takes it back.
error_panel = |failure| Elem.panel(
	Elem.PanelProps.{ label: "Directory error", width: Fill, padding: 14, gap: 8, bg: danger_bg, border_color: danger_edge },
	[
		styled_text(failure.message, danger_ink, 15),
		styled_text(failure.hint, muted, 13),
		Elem.row(
			Elem.RowProps.{ label: "Directory error actions", gap: 8 },
			[
				Elem.action_button(
					Elem.ActionButtonProps.{
						caption: "Ask again",
						label: "Ask again",
						on_press: |current, _| choose_directory(current),
						padding: 6,
						padding_left: Px(12),
						padding_right: Px(12),
						font_size: 13,
						bg: danger_button,
						hover_bg: danger_button_hover,
						fg: danger_ink,
						radius: 6,
						focus_color: accent,
					},
				),
			],
		),
	],
)

status_blocks = |status| match status {
	Busy => [busy_chip]
	Failed(failure) => [error_panel(failure)]
	Dismissed => []
	Ready => []
}

## The first screen states the bargain rather than issuing an instruction. A
## person deciding whether to hand a window a folder is owed the reason.
empty_state = |status| Elem.col(
	Elem.ColProps.{ label: "No project", width: Fill, grow: True, gap: 10, padding: 32, align: Center, justify: Center },
	[
		Elem.image(Elem.ImageProps.{ label: "No project marker", bytes: folder_icon, format: Svg, width: Px(40), height: Px(40) }),
		styled_text(
			match status {
				Dismissed => "No project chosen"
				_ => "Open a project to begin"
			},
			ink,
			17,
		),
		## Two short lines rather than one long one. This block is given the
		## whole window's width, and a sentence set to that measure is one
		## nobody reads to the end of.
		styled_text(
			match status {
				Dismissed => "The chooser was closed."
				_ => "File Explorer can reach one folder: the one you hand it."
			},
			muted,
			13,
		),
		styled_text(
			match status {
				Dismissed => "Open a project whenever you are ready."
				_ => "Opening a project asks the system for that folder, and for nothing above or beside it."
			},
			muted,
			13,
		),
	],
)

selection_panel = |state, entry| {
	size = match entry.bytes {
		None => "Size unavailable"
		Some(bytes) => "Size: ${bytes.to_str()} bytes"
	}
	## The read result belongs to the entry it came from, so a stale result can
	## never be read as evidence about the entry now selected.
	read_lines = match state.read {
		Unread => []
		ReadOf(value) => if value.name != entry.name {
			[]
		} else if value.preview == "" {
			[styled_text("Read ${value.bytes.to_str()} bytes", accent, 13)]
		} else {
			[
				styled_text("Read ${value.bytes.to_str()} bytes", accent, 13),
				Elem.row(
					Elem.RowProps.{ width: Fill, padding: 8, gap: 0, bg: ground, fg: muted, font_size: 13, font_face: Monospace, radius: 5, text_overflow: Ellipsis, overflow_x: Clip },
					[Elem.text(value.preview)],
				),
			]
		}
	}
	Elem.panel(
		Elem.PanelProps.{ label: "Selection details", width: Fill, padding: 14, gap: 8, bg: surface, border_color: rule },
		[
			Elem.row(
				Elem.RowProps.{ width: Fill, gap: 8, align: Center },
				[
					kind_mark(entry.kind, entry.name),
					styled_text("Selected: ${entry.name}", ink, 15),
				],
			),
			styled_text(size, muted, 13),
		].concat(read_lines),
	)
}

close_dialog = |name| Elem.dialog(
	Elem.DialogProps.{
		label: "Close directory confirmation",
		on_dismiss: |current, _| Action.update({ ..current, dialog: Closed }),
		bg: surface,
		fg: ink,
		border_color: rule,
		gap: 12,
	},
	[
		styled_text("Close ${name}?", ink, 17),
		styled_text("The directory grant and current view will be forgotten. Nothing on disk changes, and opening the project again asks for a fresh grant.", muted, 13),
		Elem.row(
			Elem.RowProps.{ label: "Close directory actions", gap: 8, justify: End, width: Fill },
			[
				toolbar_button("Cancel", "Cancel close directory", True, |current, _| Action.update({ ..current, dialog: Closed })),
				Elem.action_button(
					Elem.ActionButtonProps.{
						caption: "Close project",
						label: "Confirm close directory",
						on_press: |current, _| Action.update({ ..current, back: [], dialog: Closed, forward: [], read: Unread, root: None, selection: NoneSelected, status: Ready, view: Empty }),
						padding: 6,
						padding_left: Px(12),
						padding_right: Px(12),
						font_size: 13,
						bg: danger_button,
						hover_bg: danger_button_hover,
						fg: danger_ink,
						radius: 6,
						focus_color: accent,
					},
				),
			],
		),
	],
)

render : State -> Elem(State)
render = |state| {
	is_busy = state.status == Busy
	## The action that asks for authority is the only amber surface in the
	## window, and it is in the same place whether or not a project is open.
	open_button = Elem.action_button(
		Elem.ActionButtonProps.{
			caption: "Open project",
			label: "Open project",
			enabled: !is_busy,
			on_press: |current, _| choose_directory(current),
			padding: 8,
			padding_left: Px(16),
			padding_right: Px(16),
			font_size: 14,
			bg: accent,
			hover_bg: accent_hover,
			active_bg: accent_active,
			fg: accent_ink,
			radius: 7,
			focus_color: ink,
		},
	)
	heading = Elem.row(
		Elem.RowProps.{ label: "File explorer heading", width: Fill, gap: 16, align: Center, justify: Between },
		[
			Elem.col(
				Elem.ColProps.{ gap: 3 },
				[
					styled_text("File Explorer", ink, 22),
					styled_text("One granted project folder, read only", muted, 13),
				],
			),
			open_button,
		],
	)
	content = match state.view {
		Empty => Elem.panel(
			Elem.PanelProps.{ label: "Directory content", width: Fill, grow: True, padding: 0, gap: 0, bg: surface, border_color: rule, align: Center, overflow_y: Clip },
			[empty_state(state.status)],
		)
		Showing(folder) => Elem.panel(
			Elem.PanelProps.{ label: "Directory content", width: Fill, height: Fill, grow: True, padding: 12, gap: 10, bg: surface, border_color: rule, overflow_y: Clip },
			[
				Elem.row(
					Elem.RowProps.{ label: "Directory toolbar", width: Fill, gap: 8, align: Center },
					[
						toolbar_button("‹", "Back", !state.back.is_empty(), |current, _| go_back(current, folder)),
						toolbar_button("›", "Forward", !state.forward.is_empty(), |current, _| go_forward(current, folder)),
						toolbar_button("Root", "Breadcrumb root", True, |current, _| go_root(current, folder)),
						toolbar_button("Refresh", "Refresh directory", True, |current, _| refresh(current, folder)),
						Elem.row(
							Elem.RowProps.{ label: "Project path", width: Fill, grow: True, gap: 6, align: Center, overflow_x: Clip },
							path_strip(folder),
						),
						toolbar_button("Close project", "Close directory", True, |current, _| Action.update({ ..current, dialog: ConfirmClose(folder.name) })),
					],
				),
				Elem.virtual_list(Elem.VirtualListProps.{ name: "Directory entries", row_height: 34, items: entry_items(state, folder) }),
			],
		)
	}
	selection = match state.selection {
		NoneSelected => []
		Selected(entry) => [selection_panel(state, entry)]
	}
	dialog = match state.dialog {
		Closed => []
		ConfirmClose(name) => [close_dialog(name)]
	}
	Elem.col(
		Elem.ColProps.{ label: "File explorer", width: Fill, height: Fill, grow: True, padding: 20, gap: 14, overflow_y: Clip },
		[heading]
			.concat(status_blocks(state.status))
			.append(content)
			.concat(selection)
			.concat(dialog),
	)
}
