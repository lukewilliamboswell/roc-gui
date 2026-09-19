import pf.Gui
import History
import Theme
import "icons/pin.svg" as pin_icon : List(U8)
import "icons/eye-off.svg" as eye_off_icon : List(U8)
import "icons/search.svg" as search_icon : List(U8)

Render := [].{
	render : History.State -> Gui.Elem(History.State)
	render = render
}

mark = |bytes, name, size| Gui.image(
	{ label: name, bytes, format: Svg, width: Px(size), height: Px(size) },
)

## A small control. Nothing in this window is a large control: the loudest thing
## on screen should be the captured text, not the buttons around it.
chip = |caption, label, enabled, fg, on_press| Gui.button({
	caption,
	label,
	enabled,
	on_press,
	padding: 7,
	font_size: Theme.meta,
	radius: Theme.chip_radius,
	bg: Theme.surface,
	hover_bg: Theme.surface_hover,
	fg,
	border_color: Theme.edge,
	border_width: 1,
})

## The capture switch. It is filled with `live` exactly while capture is
## running, the way a recording indicator is lit while it records, and it is a
## quiet outlined control otherwise. Filling the *Start* button green would have
## put the colour that means "this window is reading you" on the screen at the
## one moment the window is guaranteed not to be.
switch = |caption, label, running, on_press| Gui.button({
	caption,
	label,
	on_press,
	padding: 8,
	font_size: Theme.meta,
	radius: Theme.chip_radius,
	bg: if running {
		Theme.live
	} else {
		Theme.surface
	},
	hover_bg: if running {
		Theme.live
	} else {
		Theme.surface_hover
	},
	fg: if running {
		Theme.on_fill
	} else {
		Theme.text
	},
	border_color: if running {
		Theme.live
	} else {
		Theme.edge
	},
	border_width: 1,
})

line = |size, fg, text| Gui.col({ font_size: size, fg }, [Gui.text(text)])

## A band across the full width of the window, under the header. Only ever one
## of them is on screen, and only when there is something true to say that the
## status line at the bottom is too quiet to carry.
band = |label, accent, icon, icon_name, headline, detail, actions| Gui.row(
	{
		label,
		width: Fill,
		padding: Theme.inset,
		gap: 10,
		align: Center,
		bg: Theme.surface,
		border_color: accent,
		border_width: 0,
		border_left: Px(3),
	},
	[
		mark(icon, icon_name, 16),
		Gui.col(
			{ grow: True, gap: 2 },
			[line(Theme.meta + 1, accent, headline), line(Theme.meta, Theme.dim, detail)],
		),
	].concat(actions),
)

## What the list shows when it has no rows. Each of these is a different fact
## about the person's data, and each one names the next move. The first-run and
## refused states are the ones that matter: this window reads a person's
## clipboard, so it has to be able to say plainly that it is not doing so yet,
## and why.
placard = |accent, headline, detail| Gui.col(
	{
		label: "History placard",
		width: Fill,
		height: Fill,
		grow: True,
		gap: 8,
		padding: 32,
		align: Center,
		justify: Center,
	},
	[
		line(Theme.body + 1, accent, headline),
		Gui.col(
			{ max_width: Px(460), font_size: Theme.meta + 1, fg: Theme.dim },
			[Gui.text(detail)],
		),
	],
)

empty_history = |state| {
	running = match state.run_state {
		Running(_, _) => True
		Paused => False
	}
	if !state.search.is_empty() and state.entries.len() > 0 {
		placard(
			Theme.text,
			"No captured item matches “${state.search}”",
			"${state.entries.len().to_str()} items are held in this window. Clear the search to see them all.",
		)
	} else {
		match state.grant {
			Denied =>
				placard(
					Theme.danger,
					"The clipboard was not granted",
					"This window can read your clipboard only through a grant it was launched with, and it was launched without one. Start it with --host-cap-clipboard and press Start capture again. Nothing has been read.",
				)
			_ if running =>
				placard(
					Theme.live,
					"Watching for changes",
					"Copy anything and it will appear here. Nothing that was on your clipboard before you pressed Start has been read.",
				)
			Held =>
				placard(
					Theme.dim,
					"Capture is paused",
					"Nothing is being read. Press Start capture to resume watching; anything copied while paused is not recorded.",
				)
			Unasked =>
				placard(
					Theme.dim,
					"Nothing has been read yet",
					"This window holds no clipboard authority until you ask for it. Press Start capture to begin watching, and Pause at any time to stop. Captured items live in this window only — they are never written anywhere.",
				)
			}
	}
}

## An entry's own row. The text is the largest thing in it, the pin mark makes a
## pinned row visible without reading its buttons, and the ordinal sits in the
## quietest tier so the column of numbers never competes with the content.
entry_row = |entry, run_state| {
	restore = match run_state {
		Paused =>
			chip("Restore", "Restore item ${entry.id.to_str()}", False, Theme.dim, |_, _| Gui.none)
		Running(_, clipboard) =>
			chip("Restore", "Restore item ${entry.id.to_str()}", True, Theme.text, |current, _| History.restore(current, entry, clipboard))
		}
	pin_gutter = if entry.pinned {
		Gui.col(
			{ label: "Pinned mark ${entry.id.to_str()}", width: Px(16), align: Center },
			[mark(pin_icon, "Pinned", 13)],
		)
	} else {
		Gui.col({ width: Px(16) }, [])
	}
	Gui.row(
		{
			label: "Clipboard item ${entry.id.to_str()}",
			width: Fill,
			gap: 10,
			padding: 12,
			align: Center,
			bg: Theme.surface,
			radius: Theme.radius,
			border_color: if entry.pinned {
				Theme.pinned
			} else {
				Theme.line
			},
			border_width: 1,
		},
		[
			pin_gutter,

			## Captured text stays on one line and ends in an ellipsis rather than
			## reflowing: a long clipping must never push an entry's own controls
			## off the end of its row, and a shortened one must never look
			## complete.
			Gui.col(
				{ width: Px(0), grow: True, gap: 3, overflow_x: Clip },
				[
					Gui.col(
						{
							width: Fill,
							height: Px(19),
							font_size: Theme.body,
							fg: Theme.text,
							text_overflow: Ellipsis,
							overflow_x: Clip,
							overflow_y: Clip,
						},
						[Gui.text(entry.text)],
					),
					line(
						Theme.meta,
						Theme.faint,
						if entry.pinned {
							"#${entry.id.to_str()} · pinned"
						} else {
							"#${entry.id.to_str()}"
						},
					),
				],
			),
			chip(
				if entry.pinned {
					"Unpin"
				} else {
					"Pin"
				},
				"Toggle pin item ${entry.id.to_str()}",
				True,
				if entry.pinned {
					Theme.pinned
				} else {
					Theme.dim
				},
				|current, _| Gui.update(History.toggle_pin(current, entry.id)),
			),
			restore,
			chip("Delete", "Delete item ${entry.id.to_str()}", True, Theme.dim, |current, _| Gui.update(History.remove(current, entry.id))),
		],
	)
}

render = |state| {
	running = match state.run_state {
		Running(_, _) => True
		Paused => False
	}
	control = match state.run_state {
		Paused => switch("Start capture", "Start clipboard capture", False, |current, _| History.start!(current))
		Running(timer, _) => switch("Pause capture", "Pause clipboard capture", True, |current, _| History.pause!(current, timer))
	}
	visible = state.entries.keep_if(|entry| state.search.is_empty() or entry.text.contains(state.search))
	pinned_count = state.entries.keep_if(|entry| entry.pinned).len()
	items = visible.map(
		|entry| { key: entry.id, content: entry_row(entry, state.run_state) },
	)
	status_fg = match state.tone {
		Live => Theme.live
		Private => Theme.privacy
		Refused => Theme.danger
		Rest => Theme.dim
	}

	## The header states what the window is doing before it states what it is.
	## A person opening a clipboard history wants the answer to "is it reading
	## me" first, and the title second.
	header = Gui.row(
		{
			label: "Application header",
			width: Fill,
			padding: Theme.inset,
			gap: 12,
			align: Center,
			bg: Theme.ground,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
		},
		[
			Gui.col(
				{ label: "Application identity", grow: True, gap: 3 },
				[
					line(Theme.title, Theme.text, "Clipboard History"),
					line(
						Theme.meta,
						if running {
							Theme.live
						} else {
							Theme.faint
						},
						if running {
							"Reading your clipboard · nothing leaves this window"
						} else {
							"Not reading your clipboard"
						},
					),
				],
			),
			control,
		],
	)

	## The only band that is ever shown, and only when it has something true to
	## say the status line cannot carry. Arming the discard is the one state a
	## person must be able to see and take back at any moment, so it is the one
	## that takes the full width of the window.
	bands = if state.private_next {
		[
			band(
				"Privacy armed",
				Theme.privacy,
				eye_off_icon,
				"Privacy armed",
				"The next copied item will be discarded",
				"It is read to learn that it changed and then dropped. It never enters this window's history, and nothing about its content is recorded.",
				[chip("Cancel", "Cancel private next", True, Theme.privacy, |current, _| Gui.update(History.cancel_private(current)))],
			),
		]
	} else {
		[]
	}

	toolbar = Gui.row(
		{
			label: "History toolbar",
			width: Fill,
			padding: Theme.inset,
			gap: 10,
			align: Center,
			bg: Theme.ground,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
		},
		[
			mark(search_icon, "Search history", 14),
			Gui.text_input({
				label: "Search history",
				value: state.search,
				placeholder: "Search captured text",
				grow: True,
				width: Px(0),
				height: Px(30),
				padding: 8,
				font_size: Theme.meta + 1,
				bg: Theme.well,
				fg: Theme.text,
				border_color: Theme.edge,
				border_width: 1,
				radius: Theme.chip_radius,
				on_change: |current, event| Gui.update(History.set_search(current, event.value)),
				on_submit: |_, _| Gui.none,
			}),

			## Arming the discard needs a running capture to mean anything, and
			## clearing needs something to clear. Offering either when it cannot
			## act would be offering a promise the window cannot keep.
			chip(
				"Discard next copy",
				"Discard next clipboard item",
				running and !state.private_next,
				Theme.privacy,
				|current, _| Gui.update(History.mark_private(current)),
			),
			chip(
				"Clear unpinned",
				"Clear unpinned history",
				state.entries.len() > pinned_count,
				Theme.dim,
				|current, _| Gui.update(History.clear_unpinned(current)),
			),
		],
	)

	## The footer is a readout, not a paragraph: the status sentence in its tone
	## on the left, and the two counts a person checks against on the right.
	footer = Gui.row(
		{
			label: "History footer",
			width: Fill,
			padding: Theme.inset,
			gap: 10,
			align: Center,
			bg: Theme.ground,
			border_color: Theme.line,
			border_width: 0,
			border_top: Px(1),
		},
		[
			Gui.row(
				{ label: "Capture status", grow: True, gap: 0, fg: status_fg, font_size: Theme.meta + 1 },
				[Gui.text(state.status)],
			),
			line(Theme.meta, Theme.faint, "${visible.len().to_str()} matching items"),
			line(Theme.meta, Theme.faint, "·"),
			line(Theme.meta, Theme.faint, "${pinned_count.to_str()} pinned"),
		],
	)

	Gui.col(
		{
			label: "Clipboard history",
			width: Fill,
			height: Fill,
			grow: True,
			gap: 0,
			bg: Theme.ground,
			fg: Theme.text,
			font_size: Theme.body,
		},
		[header].concat(bands).concat([
			toolbar,
			Gui.col(
				{
					label: "Captured items",
					width: Fill,
					height: Fill,
					grow: True,
					gap: 0,
					padding: Theme.gap,
					bg: Theme.well,
					overflow_y: Clip,
				},
				[
					if items.len() == 0 {
						empty_history(state)
					} else {
						Gui.virtual_list(
							{ label: "Clipboard items", row_height: Theme.row_height, items },
						)
					},
				],
			),
			footer,
		]),
	)
}
