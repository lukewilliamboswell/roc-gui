## The mounted console: a header, a standing readout of the one stream the
## explorer may hold, the scan bar, the keyspace, and the value inspector.
import pf.Gui
import Explorer
import RedisData
import Theme
import "icons/unplug.svg" as offline_icon : List(U8)
import "icons/plug-zap.svg" as online_icon : List(U8)
import "icons/shield-off.svg" as refused_icon : List(U8)

View := [].{
	render : Explorer.State -> Gui.Elem(Explorer.State)
	render = render
}

meta = |caption| Gui.row(
	{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

divider = Gui.row(
	{ padding: 0, gap: 0, fg: Theme.line, font_size: Theme.meta },
	[Gui.text("|")],
)

trailing_meta = |caption| Gui.row(
	{ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

note = |caption| Gui.row(
	{ width: Fill, padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.body, font_face: Theme.face },
	[Gui.text(caption)],
)

key_cap = |props| Gui.button({
	caption: props.caption,
	label: props.label,
	enabled: props.enabled,
	on_press: props.on_press,
	padding: 5,
	font_size: Theme.meta,
	font_face: Theme.face,
	radius: Theme.radius,
	bg: Theme.key,
	hover_bg: Theme.key_hover,
	active_bg: Theme.key_active,
	fg: Theme.text,
	border_color: Theme.edge,
	border_width: 1,
})

## How the explorer reads its own connection. The three icons are the three
## things it can be, and the signal colour appears only while a stream is
## actually held, so its presence is the answer at a glance.
reading_of = |state| match state.trouble {
	Some(trouble) if trouble.denied => { icon: refused_icon, name: "Endpoint refused", verdict: "the host granted no endpoint", ink: Theme.alarm_ink }
	_ => match state.link {
		Offline => { icon: offline_icon, name: "No stream held", verdict: "no stream held", ink: Theme.dim }
		Opening(_) => { icon: offline_icon, name: "Opening a stream", verdict: "opening…", ink: Theme.dim }
		Closing(_) => { icon: offline_icon, name: "Closing the stream", verdict: "closing…", ink: Theme.dim }
		Idle(_) => { icon: online_icon, name: "Stream held", verdict: "stream held, idle", ink: Theme.signal }
		Busy(busy) => { icon: online_icon, name: "Stream in use", verdict: "stream held, ${busy.doing}", ink: Theme.signal }
	}
}

## The explorer's authority is one numeric endpoint chosen by the host at
## launch. Roc is never told which, and cannot derive another, so the bar states
## the shape of the grant rather than pretending to name it, and reports what
## the explorer is actually holding against it.
endpoint_bar = |state| {
	reading = reading_of(state)
	control = match state.link {
		Idle(stream) => key_cap({ caption: "Disconnect", label: "Disconnect from Redis", enabled: True, on_press: |current, _| Explorer.disconnect(current, stream) })
		Busy(busy) => key_cap({ caption: "Disconnect", label: "Disconnect from Redis", enabled: False, on_press: |current, _| Explorer.disconnect(current, busy.stream) })
		_ => key_cap({ caption: "Connect", label: "Connect to Redis", enabled: True, on_press: |current, _| Explorer.connect(current) })
	}
	Gui.row(
		{
			label: "Endpoint bar",
			width: Fill,
			padding: Theme.inset,
			gap: Theme.inset,
			align: Center,
			bg: Theme.region,
			border_color: Theme.line,
			border_width: 0,
			border_bottom: Px(1),
			font_size: Theme.meta,
		},
		[
			Gui.image({ label: reading.name, bytes: reading.icon, format: Svg, width: Px(13), height: Px(13) }),
			meta("ENDPOINT"),
			Gui.row(
				{ padding: 0, gap: 0, fg: Theme.text, font_size: Theme.meta, font_face: Theme.face },
				[Gui.text("one address, fixed by the host at launch")],
			),
			divider,
			Gui.row(
				{ label: "Endpoint verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta, font_face: Theme.face },
				[Gui.text(reading.verdict)],
			),
			control,
		],
	)
}

error_band = |state| match state.trouble {
	Some(trouble) => Gui.panel(
		{
			label: "Redis error",
			width: Fill,
			padding: Theme.inset,
			gap: 2,
			bg: Theme.alarm,
			fg: Theme.alarm_ink,
			border_color: Theme.alarm_line,
			border_width: 0,
			border_bottom: Px(1),
			radius: 0,
		},
		[
			Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text(trouble.message)]),
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(trouble.remedy)]),
		],
	)
	None => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
}

## The scan bar exists only while a stream does. While a request owns the
## stream its controls stay in place and go dead, rather than disappearing, so
## the console does not reflow under the pointer mid-request.
scan_bar = |state| {
	held = match state.link {
		Idle(stream) => Some({ stream, ready: True })
		Busy(busy) => Some({ stream: busy.stream, ready: False })
		_ => None
	}
	match held {
		None => Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
		Some(link) => Gui.row(
			{
				label: "Scan bar",
				width: Fill,
				padding: Theme.inset,
				gap: Theme.inset,
				align: Center,
				bg: Theme.region,
				border_color: Theme.line,
				border_width: 0,
				border_bottom: Px(1),
			},
			[
				meta("SCAN"),
				Gui.text_input({
					label: "Key pattern",
					value: state.pattern,
					placeholder: "a glob, for example profile:*",
					enabled: link.ready,
					on_change: |current, event| Gui.update(Explorer.set_pattern(current, event.value)),
					on_submit: |current, _| Explorer.scan(current, link.stream),
					width: Fill,
					grow: True,
					height: Px(Theme.field_height),
					padding: Theme.inset,
					font_size: Theme.body,
					font_face: Theme.face,
					bg: Theme.well,
					fg: Theme.text,
					border_color: Theme.edge,
					border_width: 1,
					radius: Theme.radius,
				}),
				key_cap({ caption: "Refresh", label: "Refresh Redis keys", enabled: link.ready, on_press: |current, _| Explorer.scan(current, link.stream) }),
			],
		)
	}
}

## One row of the keyspace. The selected key keeps its own surface so the
## inspector on the right is always attributable to a row on the left.
key_row = |state, key, stream, ready| {
	selected = match state.selection {
		Some(selection) => selection.key.name == key.name
		None => False
	}
	Gui.button({
		caption: key.name,
		label: "Inspect Redis key ${key.name}",
		enabled: ready,
		on_press: |current, _| Explorer.inspect(current, stream, key),
		width: Fill,
		height: Px(Theme.row_height),
		padding: 0,
		padding_left: Px(Theme.inset),
		font_size: Theme.body,
		font_face: Theme.face,
		radius: 0,
		bg: if selected Theme.selected else Theme.well,
		hover_bg: Theme.key_hover,
		active_bg: Theme.key_active,
		fg: if selected Theme.text else Theme.dim,
		text_overflow: Ellipsis,
		justify: Start,
	})
}

keyspace = |state| {
	held = match state.link {
		Idle(stream) => Some({ stream, ready: True })
		Busy(busy) => Some({ stream: busy.stream, ready: False })
		_ => None
	}
	items = match held {
		None => state.keys.map_with_index(|key, index| { key: index, content: note(key.name) })
		Some(link) => state.keys.map_with_index(|key, index| { key: index, content: key_row(state, key, link.stream, link.ready) })
	}
	body = if state.keys.is_empty() {
		[
			Gui.col(
				{ width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: 0 },
				[
					note(
						match state.link {
							Offline => "Connect to read the keyspace."
							Opening(_) => "Opening the stream…"
							Closing(_) => "Closing the stream…"
							_ => "No key matches this pattern."
						},
					),
				],
			),
		]
	} else {
		[Gui.virtual_list({ label: "Redis keys", row_height: Theme.row_height, items })]
	}
	Gui.col(
		{
			label: "Keyspace",
			width: Px(Theme.keys_width),
			height: Fill,
			padding: 0,
			gap: 0,
			bg: Theme.well,
			border_color: Theme.line,
			border_width: 0,
			border_right: Px(1),
			overflow_y: Clip,
		},
		[
			Gui.row(
				{ width: Fill, padding: Theme.inset, gap: Theme.inset, bg: Theme.region, border_color: Theme.line, border_width: 0, border_bottom: Px(1) },
				[meta("KEYS"), trailing_meta("Keys: ${state.keys.len().to_str()}")],
			),
		].concat(body),
	)
}

value_lines = |selected| RedisData.lines(selected.value).map_with_index(
	|line, index| Gui.row(
		{ width: Fill, padding: 0, gap: 0, fg: Theme.text, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
		[Gui.text("Value ${index.to_str()}: ${line}")],
	),
)

inspector = |state| {
	body = match state.selection {
		None => [note("Select a key to inspect its value")]
		Some(selected) => [
			Gui.row(
				{ label: "Selected key", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[
					Gui.row(
						{ padding: 0, gap: 0, fg: Theme.text, font_size: Theme.body, font_face: Theme.face, text_overflow: Ellipsis },
						[Gui.text("Key: ${selected.key.name}")],
					),
					trailing_meta(RedisData.ttl_text(selected.ttl_ms)),
				],
			),
			meta("Type: ${RedisData.kind_name(selected.kind)}"),
			Gui.col(
				{ label: "Value", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: 2, bg: Theme.well, border_color: Theme.line, border_width: 1, radius: Theme.radius, overflow_y: Clip },
				value_lines(selected),
			),
		]
	}
	Gui.panel(
		{ label: "Value inspector", width: Fill, height: Fill, grow: True, padding: Theme.inset, gap: Theme.inset, bg: Theme.ground, border_width: 0, radius: 0 },
		body,
	)
}

header = |state| Gui.row(
	{
		label: "Explorer header",
		width: Fill,
		padding: Theme.inset,
		gap: 8,
		align: Center,
		bg: Theme.region,
		border_color: Theme.line,
		border_width: 0,
		border_bottom: Px(1),
		fg: Theme.text,
		font_size: Theme.meta,
	},
	[
		Gui.text("REDIS EXPLORER"),
		divider,
		meta("resp, read only"),
		divider,
		trailing_meta("req ${state.next_request.to_str()}"),
	],
)

render : Explorer.State -> Gui.Elem(Explorer.State)
render = |state| Gui.col(
	{
		label: "Redis Explorer",
		width: Fill,
		height: Fill,
		grow: True,
		padding: 0,
		gap: Theme.seam,
		bg: Theme.ground,
		fg: Theme.text,
		font_size: Theme.body,
	},
	[
		header(state),
		endpoint_bar(state),
		error_band(state),
		scan_bar(state),
		Gui.row(
			{ label: "Console", width: Fill, height: Fill, grow: True, padding: 0, gap: 0 },
			[keyspace(state), inspector(state)],
		),
	],
)
