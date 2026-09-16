## The window.
##
## The subject here is a physical object, and the window is arranged the way a
## person reasons about one: on the left, whether there is a device and whether
## it is open; on the right, what it is set to. The right side is empty until
## the left side is settled, because there is genuinely nothing to show -- the
## configuration is read from the device, not invented here.
##
## Every state of the connection is drawn rather than reported. Nothing
## discovered, discovery refused, discovered but closed, open, and lost each get
## their own surface, their own colour, and their own sentence about what to do
## next.
import pf.Action
import pf.Device
import pf.Elem
import pf.Gui
import Configurator
import Format
import Protocol
import Theme
import "icons/triangle-alert.svg" as alert_icon : List(U8)
import "icons/usb.svg" as usb_icon : List(U8)

View := [].{
	render : Configurator.State -> Elem.Elem(Configurator.State)
	render = render
}

devices_width = 340.U32
strip_height = 66.U32
range_width = 288.U32
range_height = 10.U32

## The exact sentence each state puts at the top of the window, and the line
## underneath that says what it means for the hardware and for the person.
copy = |status| match status {
	Ready => {
		headline: "Ready to discover devices",
		note: "Nothing has been asked of the host yet. Discovery looks only inside the grant you were given and cannot widen it.",
	}
	Discovering => {
		headline: "Discovering devices",
		note: "Asking the host which of the granted devices are present.",
	}
	Discovered(1) => {
		headline: "Found 1 device",
		note: "Nothing is open yet. Connecting reads the device's own settings back from it.",
	}
	Discovered(count) => {
		headline: "Found ${count.to_str()} devices",
		note: "Nothing is open yet. Connecting reads the device's own settings back from it.",
	}
	Connecting => {
		headline: "Connecting",
		note: "Opening the device and reading its current configuration.",
	}
	Connected => {
		headline: "Connected and synchronized",
		note: "The settings on the right were read from the device a moment ago. Nothing has been written to it.",
	}
	Dirty => {
		headline: "Unsaved changes",
		note: "These edits are held here, not on the device. Apply sends them as one transaction the device must acknowledge.",
	}
	Applying => {
		headline: "Applying configuration",
		note: "Sending one transaction and waiting for the device to acknowledge it.",
	}
	Applied => {
		headline: "Configuration applied",
		note: "The device acknowledged the transaction. Its settings and the ones shown here now agree.",
	}
	Disconnecting => {
		headline: "Disconnecting",
		note: "Closing the connection and releasing the handle.",
	}
	Disconnected => {
		headline: "Disconnected",
		note: "The handle is released. Any unapplied edit went with it; connecting again reads the device's own settings.",
	}
	Refused(message) => {
		headline: message,
		note: "The host granted no device, so nothing was searched for and nothing was opened. Grant a device and press Discover again.",
	}
	Lost(message) => {
		headline: message,
		note: "The connection has been given up and its handle released. Discover again to find the device.",
	}
}

## The word beside the link light. Five words for five situations, so the pill
## is never the same for a device that is present and one that is open.
link_word = |status| match status {
	Ready | Disconnected => "No device"
	Discovering | Connecting | Disconnecting => "Working"
	Discovered(_) => "Found"
	Connected | Dirty | Applying | Applied => "Connected"
	Refused(_) => "Blocked"
	Lost(_) => "Lost"
}

link_colour = |status| match status {
	Connected | Applied => Theme.link
	Dirty | Applying => Theme.pending
	Refused(_) | Lost(_) => Theme.alarm
	_ => Theme.muted
}

alarmed = |status| match status {
	Refused(_) | Lost(_) => True
	_ => False
}

mark = |bytes, name, size| Elem.image(
	Elem.ImageProps.{ label: name, bytes, format: Svg, width: Px(size), height: Px(size) },
)

pill = |status| Elem.row(
	Elem.RowProps.{
		label: "Link state",
		min_width: Px(128),
		height: Px(36),
		padding: 14,
		gap: 9,
		radius: 18,
		align: Center,
		bg: Theme.raised,
		border_color: Theme.hairline,
		border_width: 1,
	},
	[Theme.dot(link_colour(status)), Theme.figure(link_word(status), 13, link_colour(status))],
)

header = |state| Elem.row(
	Elem.RowProps.{ label: "Header", width: Fill, padding: 0, gap: 16, align: Center },
	[
		Elem.col(
			Elem.ColProps.{ label: "Wordmark", grow: True, padding: 0, gap: 4 },
			[
				Elem.row(
					Elem.RowProps.{ padding: 0, gap: 0, font_size: 20, font_weight: 700, fg: Theme.ink },
					[Elem.text("Device Configurator")],
				),
				Theme.note("One granted peripheral, its settings read from it and written back"),
			],
		),
		pill(state.status),
	],
)

status_strip = |state| {
	said = copy(state.status)
	troubled = alarmed(state.status)
	Elem.row(
		Elem.RowProps.{
			label: "Status",
			width: Fill,
			height: Px(strip_height),
			min_height: Px(strip_height),
			padding: 14,
			gap: 12,
			radius: 10,
			align: Center,
			overflow_y: Clip,
			bg: if troubled Theme.alarm_tint else Theme.surface,
			border_color: if troubled Theme.alarm_edge else Theme.hairline,
			border_width: 1,
		},
		(if troubled [mark(alert_icon, "Attention mark", 18)] else []).concat(
			[
				Elem.col(
					Elem.ColProps.{ label: "Status detail", grow: True, padding: 0, gap: 3 },
					[
						Elem.row(
							Elem.RowProps.{
								padding: 0,
								gap: 0,
								font_size: 14,
								font_weight: 600,
								fg: if troubled Theme.alarm else Theme.ink,
								text_overflow: Ellipsis,
							},
							[Elem.text(said.headline)],
						),
						Elem.row(
							Elem.RowProps.{ padding: 0, gap: 0, font_size: 12, fg: Theme.muted, text_overflow: Ellipsis },
							[Elem.text(said.note)],
						),
					],
				),
			],
		),
	)
}

## One card per discovered device. The card is where the connection lives: it
## offers Connect while it is closed and Disconnect while it is open, and never
## both. A Disconnect control for a device nobody connected is not a safeguard,
## it is a button whose only possible outcome is an apology.
device_card = |state, index, device| {
	open = state.connected != None
	Elem.col(
		Elem.ColProps.{
			label: "Device ${index.to_str()}",
			width: Fill,
			padding: 12,
			gap: 8,
			radius: 10,
			bg: if open Theme.link_tint else Theme.raised,
			border_color: if open Theme.link_deep else Theme.hairline,
			border_width: 1,
		},
		[
			Elem.row(
				Elem.RowProps.{ width: Fill, padding: 0, gap: 8, align: Center },
				[
					mark(usb_icon, "Device mark", 16),
					Elem.col(
						Elem.ColProps.{ grow: True, padding: 0, gap: 0, font_size: 14, fg: Theme.ink, text_overflow: Ellipsis },
						[Elem.text("Device ${index.to_str()}: ${device.manufacturer} ${device.product}")],
					),
				],
			),
			Theme.figure("USB ${Format.hex4(device.vendor_id)}:${Format.hex4(device.product_id)}", 11, Theme.absent),
			match state.connected {
				Some(connection) => Elem.row(
					Elem.RowProps.{ width: Fill, padding: 0, gap: 10, align: Center },
					[
						Theme.dot(Theme.link),
						Elem.col(Elem.ColProps.{ grow: True, padding: 0, gap: 0, font_size: 12, fg: Theme.link }, [Elem.text("Open")]),
						Theme.secondary("Disconnect", "Disconnect device", True, |current, _| Configurator.disconnect(current, connection)),
					],
				)
				None => Theme.primary("Connect", "Connect device", True, |current, _| Configurator.connect(current))
			},
		],
	)
}

## Nothing discovered is a state with a shape, not an empty box. It says what
## discovery will and will not do, which is the part a person cannot guess.
nothing_found = |state| Elem.col(
	Elem.ColProps.{
		label: "No devices",
		width: Fill,
		padding: 18,
		gap: 8,
		radius: 10,
		align: Center,
		bg: Theme.raised,
		border_color: Theme.hairline,
		border_width: 1,
	},
	[
		mark(usb_icon, "Device mark", 28),
		Theme.note(if alarmed(state.status) "Nothing was searched for." else "No device discovered yet."),
		Elem.col(
			Elem.ColProps.{ width: Fill, padding: 0, gap: 0, font_size: 11, fg: Theme.absent, align: Center },
			[Elem.text("Access is granted one device at a time, outside this window.")],
		),
	],
)

devices_panel = |state| Theme.panel(
	"Devices",
	Px(devices_width),
	[
		Theme.caption("GRANTED DEVICES"),
		if state.devices.is_empty() {
			nothing_found(state)
		} else {
			Elem.col(
				Elem.ColProps.{ label: "Discovered devices", width: Fill, padding: 0, gap: 10 },
				state.devices.map_with_index(|device, index| device_card(state, index, device)),
			)
		},
		Theme.secondary(
			if state.devices.is_empty() "Discover devices" else "Discover again",
			"Discover devices",
			state.connected == None,
			|current, _| Configurator.discover(current),
		),
	].concat(
		## Searching again empties the list, and the open connection lives on the
		## card in that list. Offering the search while a handle is open would let
		## a person strand it with one press, so it is withheld and the reason is
		## given where the control is.
		match state.connected {
			Some(_) => [Theme.aside("Disconnect before searching again.")]
			None => []
		},
	),
)

## The sensitivity range, drawn rather than described. A number between two
## bounds is a position, and a position is quicker to read than a comparison.
range = |sensitivity| {
	span = Configurator.sensitivity_ceiling - Configurator.sensitivity_floor
	filled = U16.to_u32(sensitivity - Configurator.sensitivity_floor) * range_width / U16.to_u32(span)
	Elem.canvas(
		Elem.CanvasProps.{
			label: "Sensitivity range",
			primitives: [
				Rectangle(
					Elem.CanvasRectangle.{ key: 1, label: "Range track", x: 0, y: 0, width: range_width, height: range_height, fill: Gui.rgb(0x151b1f), radius: 5 },
				),
				Rectangle(
					Elem.CanvasRectangle.{ key: 2, label: "Range fill", x: 0, y: 0, width: if filled < 4 4 else filled, height: range_height, fill: Theme.link_deep, radius: 5 },
				),
			],
			on_pointer: |_, _| Action.none,
			width: Px(range_width),
			height: Px(range_height),
			min_width: Px(range_width),
			min_height: Px(range_height),
			bg: Gui.rgb(0x151b1f),
			radius: 5,
		},
	)
}

step_button = |caption, label, press| Elem.action_button(
	Elem.ActionButtonProps.{
		caption,
		label,
		on_press: press,
		width: Px(38),
		height: Px(38),
		padding: 0,
		radius: 19,
		font_size: 18,
		font_weight: 600,
		bg: Theme.raised,
		hover_bg: Gui.rgb(0x303a41),
		active_bg: Gui.rgb(0x1e262b),
		fg: Theme.ink,
		border_color: Theme.hairline,
		border_width: 1,
	},
)

sensitivity_field = |config| Elem.col(
	Elem.ColProps.{ label: "Sensitivity", width: Fill, padding: 0, gap: 10 },
	[
		Theme.caption("SENSITIVITY"),
		Elem.row(
			Elem.RowProps.{ width: Fill, padding: 0, gap: 16, align: Center },
			[
				Elem.row(
					Elem.RowProps.{ padding: 0, gap: 6, align: Baseline, min_width: Px(120) },
					[
						Theme.figure(config.sensitivity.to_str(), 30, Theme.ink),
						Elem.row(
							Elem.RowProps.{ padding: 0, gap: 0, font_size: 12, font_weight: 700, fg: Theme.muted },
							[Elem.text("DPI")],
						),
					],
				),
				step_button("−", "Decrease sensitivity", |current, _| Action.update(Configurator.change_sensitivity(current, False))),
				step_button("+", "Increase sensitivity", |current, _| Action.update(Configurator.change_sensitivity(current, True))),
			],
		),
		range(config.sensitivity),
		Theme.aside(
			"${Configurator.sensitivity_floor.to_str()} – ${Configurator.sensitivity_ceiling.to_str()} DPI in steps of ${Configurator.sensitivity_step.to_str()}",
		),
	],
)

profile_button = |profile, active| Elem.action_button(
	Elem.ActionButtonProps.{
		caption: profile.to_str(),
		label: "Select profile ${profile.to_str()}",
		on_press: |current, _| Action.update(Configurator.select_profile(current, profile)),
		width: Px(44),
		height: Px(34),
		padding: 0,
		radius: 8,
		font_size: 14,
		font_weight: 600,
		bg: if active Theme.link_tint else Theme.raised,
		hover_bg: if active Theme.link_tint else Gui.rgb(0x303a41),
		active_bg: Gui.rgb(0x1e262b),
		fg: if active Theme.link else Theme.muted,
		border_color: if active Theme.link_deep else Theme.hairline,
		border_width: 1,
	},
)

## A device with five profiles and no sign of which one is chosen makes a person
## count presses. The selected one is lit, and the caption says which it is.
profile_field = |config| Elem.col(
	Elem.ColProps.{ label: "Profile", width: Fill, padding: 0, gap: 8 },
	[
		Theme.caption("PROFILE ${config.profile.to_str()} OF 5"),
		Elem.row(
			Elem.RowProps.{ label: "Profile controls", padding: 0, gap: 8 },
			[1, 2, 3, 4, 5].map(|profile| profile_button(profile, profile == config.profile)),
		),
	],
)

control_items = |count| {
	var $items = []
	var $index = 0
	while $index < U16.to_u64(count) {
		key = $index
		$items = $items.append(
			Elem.VirtualListItem.{
				key,
				content: Theme.figure("Control ${($index + 1).to_str()}: Primary action", 12, Theme.muted),
			},
		)
		$index = $index + 1
	}
	$items
}

## The apply footer says why it cannot be pressed when it cannot. A disabled
## control with no explanation is the defect; a message in a status field nobody
## can reach was only ever the symptom.
apply_footer = |state, connection, config| Elem.row(
	Elem.RowProps.{
		label: "Apply",
		width: Fill,
		padding: 12,
		gap: 12,
		radius: 10,
		align: Center,
		bg: if state.dirty Theme.pending_tint else Theme.raised,
		border_color: if state.dirty Theme.pending_deep else Theme.hairline,
		border_width: 1,
	},
	[
		Elem.col(
			Elem.ColProps.{ grow: True, padding: 0, gap: 2 },
			[
				Elem.row(
					Elem.RowProps.{ padding: 0, gap: 0, font_size: 13, fg: if state.dirty Theme.pending else Theme.muted },
					[Elem.text(if state.dirty "Held here, not on the device" else "The device has everything shown here")],
				),
				Theme.aside("Apply sends the whole configuration as one transaction the device must acknowledge."),
			],
		),
		Theme.primary("Apply changes", "Apply configuration", state.dirty, |current, _| Configurator.apply(current, connection, config)),
	],
)

settings_panel = |state| Theme.panel(
	"Configuration",
	Fill,
	match { config: state.config, connection: state.connected } {
		{ config: Some(config), connection: Some(connection) } => [
			sensitivity_field(config),
			Elem.checkbox(
				Elem.CheckboxProps.{
					label: "Device lighting",
					checked: config.lighting,
					on_change: |current, event| Action.update(Configurator.toggle_lighting(current, event.checked)),
					font_size: 14,
					fg: Theme.ink,
					box_checked_bg: Theme.link_deep,
					box_border: Theme.hairline,
				},
			),
			profile_field(config),
			Elem.col(
				Elem.ColProps.{ label: "Controls", width: Fill, height: Fill, grow: True, padding: 0, gap: 8, overflow_y: Clip },
				[
					Theme.caption("CONTROLS ON THIS DEVICE"),
					Elem.virtual_list(
						Elem.VirtualListProps.{ label: "Device controls", row_height: 22, items: control_items(config.controls) },
					),
				],
			),
			apply_footer(state, connection, config),
		]
		_ => [
			Theme.caption("CONFIGURATION"),
			Elem.col(
				Elem.ColProps.{
					label: "No configuration",
					width: Fill,
					height: Fill,
					grow: True,
					padding: 24,
					gap: 8,
					align: Center,
					justify: Center,
				},
				[
					Theme.note("Connect to inspect configuration"),
					Elem.col(
						Elem.ColProps.{ padding: 0, gap: 0, font_size: 11, fg: Theme.absent, align: Center, max_width: Px(320) },
						[Elem.text("Sensitivity, lighting, profile, and the control inventory are read from the device itself, so there is nothing to show until one is open.")],
					),
				],
			),
		]
	},
)

render = |state| Elem.col(
	Elem.ColProps.{
		label: "Device Configurator",
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
		Elem.row(
			Elem.RowProps.{ label: "Body", width: Fill, height: Fill, grow: True, padding: 0, gap: 16, align: Stretch },
			[devices_panel(state), settings_panel(state)],
		),
	],
)
