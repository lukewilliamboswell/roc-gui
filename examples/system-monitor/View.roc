## The window.
##
## The layout is built around one rule: a figure that changes must never move
## anything. Every tile is a fixed height, the status strip is a fixed height,
## the state pill has a floor on its width, the plot is a fixed height and is
## drawn for the width it is given, and every number is set in the fixed-pitch face. What is left free to change is
## the numbers themselves, which is the only thing a person is watching.
import pf.Gui
import Chart
import Format
import Monitor
import Processes
import Summary
import Theme
import "icons/triangle-alert.svg" as alert_icon : List(U8)

View := [].{
	render : Monitor.State -> Gui.Elem(Monitor.State)
	render = render
}

sidebar_width = 420.U32

tile_height = 102.U32

strip_height = 62.U32

## The word in the pill. Short, because it is read beside the indicator rather
## than instead of it; the sentence lives in the strip below.
state_word = |status| match status {
	Idle => "Idle"
	Live => "Live"
	Paused => "Paused"
	Refused => "Blocked"
	Failed(_) => "Stopped"
}

state_colour = |status| match status {
	Idle => Theme.muted
	Live => Theme.accent
	Paused => Theme.muted
	Refused => Theme.alert
	Failed(_) => Theme.warn
}

## What the control offers next. The accessibility name stays fixed on the two
## transitions the application actually has, so a specification and a screen
## reader both keep naming the same control while its caption changes.
control = |state| match state.run_state {
	Running(session) => Gui.button({
		caption: "Pause",
		label: "Pause sampling",
		on_press: |current, _| Monitor.pause!(current, session),
		width: Px(124),
		height: Px(38),
		radius: 19,
		font_size: 14,
		font_weight: 600,
		bg: Theme.raised,
		hover_bg: 0x24404b,
		active_bg: 0x16272e,
		fg: Theme.ink,
		border_color: Theme.hairline,
		border_width: 1,
	})
	Paused => Gui.button({
		caption: match state.status {
			Idle => "Start"
			Refused | Failed(_) => "Try again"
			_ => "Resume"
		},
		label: "Resume sampling",
		on_press: |current, _| Monitor.start!(current),
		width: Px(124),
		height: Px(38),
		radius: 19,
		font_size: 14,
		font_weight: 600,
		bg: Theme.accent,
		hover_bg: 0x7ad2e0,
		active_bg: Theme.accent_deep,
		fg: Theme.on_accent,
	})
}

pill = |status| Gui.row(
	{
		label: "Sampling state",
		min_width: Px(112),
		height: Px(38),
		padding: 14,
		gap: 9,
		radius: 19,
		align: Center,
		bg: Theme.raised,
		border_color: Theme.hairline,
		border_width: 1,
	},
	[Theme.dot(state_colour(status)), Theme.figure(state_word(status), 13, state_colour(status))],
)

header = |state| Gui.row(
	{ label: "Header", width: Fill, padding: 0, gap: 16, align: Center },
	[
		Gui.col(
			{ label: "Wordmark", grow: True, padding: 0, gap: 4 },
			[
				Gui.row(
					{ padding: 0, gap: 0, font_size: 20, font_weight: 700, fg: Theme.ink },
					[Gui.text("System Monitor")],
				),
				Theme.note("Read-only observation of this machine, for as long as you allow it"),
			],
		),
		pill(state.status),
		control(state),
	],
)

## What the state means, said once, in the one place that is always the same
## size. A refusal is not an error string dropped into a status field: it is
## this surface, with what happened, what it means, and what to press.
strip_copy = |state| match state.status {
	Idle => {
		headline: "Nothing is being read from this machine",
		note: "Start asks the host for a read-only sampler. Until then no counter, no process, and no name has been read.",
	}
	Live => {
		headline: "Sampling. ${state.history.len().to_str()} of ${Monitor.capacity.to_str()} samples held",
		note: "The window keeps the most recent samples and discards the oldest. Pause closes the sampler and its timer.",
	}
	Paused => {
		headline: "Paused. The sampler and its timer are closed",
		note: "The readings below are the last sample taken, not current values. Resume opens a new session.",
	}
	Refused => {
		headline: "System observation access denied",
		note: "The host did not grant a sampler, so nothing has been read and nothing is held. Grant observation and press Try again.",
	}
	Failed(message) => {
		headline: message,
		note: "The session was closed and its resources released. Try again opens a new one.",
	}
}

troubled = |status| match status {
	Refused | Failed(_) => True
	_ => False
}

mark = Gui.image({ label: "Attention mark", bytes: alert_icon, format: Svg, width: Px(18), height: Px(18) })

status_strip = |state| {
	copy = strip_copy(state)
	alarmed = troubled(state.status)
	Gui.row(
		{
			label: "Status",
			width: Fill,
			height: Px(strip_height),
			min_height: Px(strip_height),
			padding: 14,
			gap: 12,
			radius: 10,
			align: Center,
			overflow_y: Clip,
			bg: if alarmed 0x261a18 else Theme.surface,
			border_color: if alarmed 0x5a3a33 else Theme.hairline,
			border_width: 1,
		},
		(if alarmed [mark] else []).concat([
			Gui.col(
				{ label: "Status detail", grow: True, padding: 0, gap: 3 },
				[
					Gui.row(
						{
							padding: 0,
							gap: 0,
							font_size: 14,
							font_weight: 600,
							fg: if alarmed Theme.alert else Theme.ink,
							text_overflow: Ellipsis,
						},
						[Gui.text(copy.headline)],
					),
					Gui.row(
						{ padding: 0, gap: 0, font_size: 12, fg: Theme.muted, text_overflow: Ellipsis },
						[Gui.text(copy.note)],
					),
				],
			),
		]),
	)
}

## A reading's colours. The rule across the top of a tile is the fastest thing
## on screen to read, so it carries the level and the figure repeats it.
tile_tone = |level| match level {
	Measured => { bg: Theme.surface, detail: Theme.muted, rule: Theme.hairline, value: Theme.ink }
	Elevated => { bg: Theme.surface, detail: Theme.muted, rule: Theme.warn, value: Theme.warn }
	Critical => { bg: Theme.surface, detail: Theme.muted, rule: Theme.alert, value: Theme.alert }
	Missing => { bg: 0x101c22, detail: Theme.absent, rule: Theme.absent, value: Theme.absent }
	Pending => { bg: Theme.surface, detail: Theme.muted, rule: Theme.hairline, value: Theme.absent }
}

## An unreported reading is recessed as well as greyed. Reaching for a second
## signal is the point: a person who cannot tell these two greys apart still has
## a tile that sits lower than its neighbours, and a sentence that names it.
tile = |reading| {
	tone = tile_tone(reading.level)
	Gui.col(
		{
			label: "${reading.caption} reading",
			width: Fill,
			grow: True,
			# A reading gives up width before the page does: its figures are
			# clipped at the tile's edge rather than widening the window's
			# content past the window.
			min_width: Px(0),
			overflow_x: Clip,
			height: Px(tile_height),
			min_height: Px(tile_height),
			padding: 0,
			gap: 0,
			radius: 12,
			overflow_y: Clip,
			bg: tone.bg,
			border_color: Theme.hairline,
			border_width: 1,
		},
		[
			Theme.rule(tone.rule, 3),
			Gui.col(
				{ width: Fill, padding: 14, gap: 6 },
				[
					Theme.caption(reading.caption),
					Gui.row(
						{ padding: 0, gap: 5, align: Baseline },
						[
							Theme.figure(reading.value, 26, tone.value),
							Gui.row(
								{ padding: 0, gap: 0, font_size: 12, font_weight: 700, fg: Theme.muted },
								[Gui.text(reading.unit)],
							),
						],
					),
					Gui.row(
						{ padding: 0, gap: 0, font_size: 12, fg: tone.detail, text_overflow: Ellipsis },
						[Gui.text(reading.detail)],
					),
				],
			),
		],
	)
}

readings = |state| Gui.row(
	{ label: "Readings", width: Fill, padding: 0, gap: 12 },
	Summary.tiles(state.latest).map(tile),
)

axis = Gui.col(
	{
		label: "Load axis",
		width: Px(34),
		min_width: Px(34),
		height: Px(Chart.height),
		padding: 0,
		gap: 0,
		align: End,
		justify: Between,
	},
	Chart.gridline_captions.map(|caption| Theme.figure(caption, 10, Theme.absent)),
)

plot = |state| Theme.panel(
	"CPU history",
	"CPU LOAD OVER THE LAST ${Monitor.capacity.to_str()} SAMPLES",
	[
		Gui.row(
			{ width: Fill, padding: 0, gap: 12, align: Center, justify: End },
			[Theme.figure("newest at right", 11, Theme.absent)],
		),
		Gui.row(
			{ label: "Plot", width: Fill, padding: 0, gap: 8, align: Start },
			[
				axis,
				Chart.render({
					history: Chart.loads(state.history),
					capacity: Monitor.capacity,
					width: state.plot_width,
					on_size: |current, laid_out| if laid_out.width == current.plot_width Gui.none else Gui.update({ ..current, plot_width: laid_out.width }),
				}),
			],
		),
	],
)

## Newest first. A log that can only show its first rows should show the rows a
## person came to read.
log_items = |history| {
	held = history.len()
	var $items = []
	var $position = 0
	while $position < held {
		snapshot = history.get(held - 1 - $position)
		colour = if $position == 0 Theme.ink else Theme.muted
		$items = match snapshot {
			Ok(value) => $items.append(
				{ key: $position, content: Theme.figure(Summary.history_line(value), 12, colour) },
			)
			Err(_) => $items
		}
		$position = $position + 1
	}
	$items
}

log = |state| Theme.panel(
	"Observation log",
	"OBSERVATION LOG",
	[
		if state.history.is_empty() {
			Theme.note("No samples yet.")
		} else {
			Gui.virtual_list(
				{ label: "Observation history", row_height: 22, items: log_items(state.history) },
			)
		},
	],
)

## The sort control says which sort is in force. Two buttons that look identical
## whichever is active leave a person to infer the order from the rows, which is
## exactly the thing the control was supposed to save them doing.
sort_button = |caption, label, active, press| Gui.button({
	caption,
	label,
	on_press: press,
	height: Px(30),
	padding: 14,
	radius: 15,
	font_size: 12,
	font_weight: 600,
	bg: if active Theme.accent_tint else Theme.raised,
	hover_bg: if active Theme.accent_tint else 0x24404b,
	active_bg: 0x16272e,
	fg: if active Theme.accent else Theme.muted,
	border_color: if active Theme.accent_deep else Theme.hairline,
	border_width: 1,
})

sort_controls = |state| Gui.row(
	{ label: "Process sorting", padding: 0, gap: 8, align: Center },
	[
		Theme.caption("SORT"),
		sort_button("CPU", "Sort processes by CPU", state.sort == ByCpu, |current, _| Gui.update({ ..current, sort: ByCpu })),
		sort_button("Memory", "Sort processes by memory", state.sort == ByMemory, |current, _| Gui.update({ ..current, sort: ByMemory })),
	],
)

filter_field = |state| Gui.text_input({
	label: "Filter processes",
	value: state.filter,
	placeholder: "Filter by name",
	on_change: |current, event| Gui.update({ ..current, filter: event.value }),
	on_submit: |current, _| Gui.update(current),
	width: Fill,
	height: Px(34),
	font_size: 13,
	font_face: Monospace,
	bg: 0x0f1c23,
	border_color: Theme.hairline,
	fg: Theme.ink,
})

## A selection that outlives the process it named is ordinary on a machine that
## is still running, and it is better said than left as a number pointing at
## nothing.
selection_strip = |state, processes| Gui.col(
	{
		label: "Selection",
		width: Fill,
		height: Px(50),
		min_height: Px(50),
		padding: 10,
		gap: 3,
		radius: 8,
		overflow_y: Clip,
		bg: 0x0f1c23,
		border_color: Theme.hairline,
		border_width: 1,
	},
	match state.selected {
		None => [Theme.note("No process selected"), Theme.figure("Choose a row to hold it while the table changes", 11, Theme.absent)]
		Some(pid) => [
			Theme.figure("Selected process ${pid.to_str()}", 13, Theme.accent),
			match Processes.find(processes, pid) {
				None => Theme.figure("no longer in this sample", 11, Theme.absent)
				Some(process) => Theme.figure(Processes.row_text(process), 11, Theme.muted)
			},
		]
	},
)

process_row = |state, process| {
	chosen = state.selected == Some(process.pid)
	Gui.button({
		caption: Processes.row_text(process),
		label: "Inspect process ${process.name}",
		on_press: |current, _| Gui.update({ ..current, selected: Some(process.pid) }),
		width: Fill,
		height: Px(26),
		padding: 8,
		radius: 5,
		font_size: 12,
		font_face: Monospace,
		bg: if chosen Theme.accent_tint else 0x0f1c23,
		hover_bg: 0x1a2f38,
		active_bg: 0x16272e,
		fg: if chosen Theme.accent else Theme.ink,
		border_color: if chosen Theme.accent else 0x0f1c23,
		border_width: 2,
		border_top: Px(0),
		border_right: Px(0),
		border_bottom: Px(0),
	})
}

process_table = |state, processes| {
	visible = Processes.filter_sort(processes, state.filter, state.sort)
	rows = if visible.is_empty() {
		[Theme.figure("No process matches “${state.filter}”", 12, Theme.absent)]
	} else {
		[
			Gui.virtual_list({
				label: "Process table",
				row_height: 30,
				items: visible.map(|process| { key: process.pid, content: process_row(state, process) }),
			}),
		]
	}
	[
		Gui.row(
			{ width: Fill, padding: 0, gap: 0 },
			[Theme.figure("Processes: ${List.len(processes).to_str()}", 13, Theme.muted)],
		),
		sort_controls(state),
		filter_field(state),
		selection_strip(state, processes),
		Theme.figure(Processes.heading, 11, Theme.absent),
	].concat(rows)
}

process_panel = |state| Gui.panel(
	{
		label: "Processes",
		heading: "PROCESSES",
		heading_size: 11,
		heading_weight: 700,
		heading_color: Theme.muted,
		width: Px(sidebar_width),
		min_width: Px(sidebar_width),
		height: Fill,
		grow: True,
		padding: 16,
		gap: 10,
		radius: 12,
		overflow_y: Clip,
		bg: Theme.surface,
		border_color: Theme.hairline,
		fg: Theme.ink,
		font_size: 14,
	},
	match state.latest {
		None => [Theme.note("The table appears with the first sample.")]
		Some(snapshot) => match snapshot.processes {
			Unavailable(_) => [Theme.note("Processes are not reported"), Theme.figure("This system did not return a process list.", 11, Theme.absent)]
			Value(processes) => process_table(state, processes)
		}
	},
)

render = |state| Gui.col(
	{
		label: "System monitor",
		width: Fill,
		height: Fill,
		grow: True,
		padding: 20,
		gap: 16,
		bg: Theme.ground,
		fg: Theme.ink,
		font_size: 14,
	},
	[
		header(state),
		status_strip(state),
		Gui.row(
			{ label: "Body", width: Fill, height: Fill, grow: True, padding: 0, gap: 16, align: Stretch },
			[
				Gui.col(
					{ label: "Instruments", width: Fill, height: Fill, grow: True, min_width: Px(0), padding: 0, gap: 12 },
					[readings(state), plot(state), log(state)],
				),
				process_panel(state),
			],
		),
	],
)
