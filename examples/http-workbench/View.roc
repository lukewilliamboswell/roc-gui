## The mounted bench: a header, a standing authority readout, the request
## document on the left, and the response readout on the right.
import pf.Gui
import Theme
import Workbench
import "icons/shield.svg" as shield_icon : List(U8)
import "icons/shield-check.svg" as shield_check_icon : List(U8)
import "icons/shield-off.svg" as shield_off_icon : List(U8)

View := [].{
	render : Workbench.State -> Gui.Elem(Workbench.State)
	render = render
}

## A run of quiet type: a label, a unit, a count. Never a thing a person edits.
meta = |caption| Gui.row(
	{ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

## The hairline pipe that separates two readouts inside one region.
divider = Gui.row(
	{ padding: 0, gap: 0, fg: Theme.line, font_size: Theme.meta },
	[Gui.text("|")],
)

## The last readout of a region sits at the far edge. It grows into whatever is
## left over and justifies its own text to the end, so no spacer element exists
## only to push it there.
trailing_meta = |caption| Gui.row(
	{ padding: 0, gap: 0, grow: True, justify: End, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face },
	[Gui.text(caption)],
)

## A field's name, set in the fixed left gutter that runs down the request side
## so every editor starts on the same vertical line.
field_label = |caption| Gui.row(
	{ padding: 0, gap: 0, width: Px(62), fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face, align: Center },
	[Gui.text(caption)],
)

well_style = { bg: Theme.well, fg: Theme.text, border_color: Theme.edge, border_width: 1, radius: Theme.radius }

input = |props| Gui.text_input({
	label: props.label,
	value: props.value,
	placeholder: props.placeholder,
	on_change: props.on_change,
	on_submit: |current, _| Workbench.send(current),
	width: props.width,
	grow: props.grow,
	height: Px(Theme.field_height),
	padding: Theme.inset,
	font_size: Theme.body,
	font_face: Theme.face,
	bg: well_style.bg,
	fg: well_style.fg,
	border_color: well_style.border_color,
	border_width: well_style.border_width,
	radius: well_style.radius,
})

field_row = |caption, children| Gui.row(
	{ width: Fill, padding: 0, gap: Theme.inset, align: Center },
	[field_label(caption)].concat(children),
)

key_cap = |props| Gui.button({
	caption: props.caption,
	label: props.label,
	enabled: props.enabled,
	on_press: props.on_press,
	padding: 6,
	font_size: Theme.meta,
	radius: Theme.radius,
	bg: props.bg,
	hover_bg: props.hover_bg,
	active_bg: props.active_bg,
	fg: Theme.text,
	border_color: Theme.edge,
	border_width: 1,
})

## The bench holds authority over exactly one origin, and only a send can
## discover whether it holds it. The bar therefore reports two different things
## at once: the origin the URL field currently points at, and the verdict the
## last exercised send returned. When those disagree the verdict is shown
## against the origin it was actually about, because a grant for one origin says
## nothing about another.
authority_bar = |state| {
	next_origin = Workbench.origin_of(state.url)
	shown = if Str.is_empty(next_origin) "no origin in the URL field" else next_origin
	reading = match state.authority {
		Unexercised => { icon: shield_icon, name: "Authority not yet exercised", verdict: "not yet exercised", ink: Theme.dim }
		Granted(origin) => { icon: shield_check_icon, name: "Authority granted", verdict: "granted for ${origin}", ink: Theme.signal }
		Refused(origin) => { icon: shield_off_icon, name: "Authority refused", verdict: "refused for ${origin}", ink: Theme.alarm_ink }
	}
	Gui.row(
		{
			label: "Authority bar",
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
			meta("ORIGIN"),
			Gui.row(
				{ padding: 0, gap: 0, fg: Theme.text, font_size: Theme.meta, font_face: Theme.face, text_overflow: Ellipsis },
				[Gui.text(shown)],
			),
			divider,
			Gui.row(
				{ label: "Authority verdict", padding: 0, gap: 0, grow: True, justify: End, fg: reading.ink, font_size: Theme.meta, font_face: Theme.face },
				[Gui.text(reading.verdict)],
			),
		],
	)
}

## A refusal is a condition of the bench, not a decoration on a control, so it
## occupies a full-width band directly under the authority it contradicts. It
## carries two lines: what the host said, and the one thing a person can do.
error_band = |state| if Str.is_empty(state.error) {
	Gui.row({ padding: 0, gap: 0, height: Px(0) }, [])
} else {
	Gui.panel(
		{
			label: "Request error",
			width: Fill,
			padding: Theme.inset,
			gap: 2,
			bg: Theme.alarm,
			fg: Theme.alarm_ink,
			border_color: Theme.alarm_line,
			border_width: 0,
			border_bottom: Px(1),
			radius: 0,
			font_size: Theme.meta,
		},
		[
			Gui.row({ padding: 0, gap: 0, font_size: Theme.body }, [Gui.text(state.error)]),
			Gui.row({ padding: 0, gap: 0, fg: Theme.dim, font_size: Theme.meta, font_face: Theme.face }, [Gui.text(state.remedy)]),
		],
	)
}

request_side = |state| Gui.col(
	{
		label: "Request document",
		width: Px(Theme.request_width),
		height: Fill,
		padding: 10,
		gap: 8,
		bg: Theme.ground,
		border_color: Theme.line,
		border_width: 0,
		border_right: Px(1),
	},
	[
		meta("REQUEST"),
		field_row(
			"METHOD",
			[
				input({ label: "HTTP method", value: state.method, placeholder: "POST", on_change: |current, event| Gui.update(Workbench.set_method(current, event.value)), width: Px(96), grow: False }),
				trailing_meta("${state.request.to_utf8().len().to_str()} B body"),
			],
		),
		field_row("URL", [input({ label: "Request URL", value: state.url, placeholder: "http://127.0.0.1:38191/echo", on_change: |current, event| Gui.update(Workbench.set_url(current, event.value)), width: Fill, grow: True })]),
		field_row("QUERY", [input({ label: "Query parameters", value: state.query, placeholder: "page=1&limit=100", on_change: |current, event| Gui.update(Workbench.set_query(current, event.value)), width: Fill, grow: True })]),
		field_row(
			"HEADER",
			[
				input({ label: "Header name", value: state.header_name, placeholder: "accept", on_change: |current, event| Gui.update(Workbench.set_header_name(current, event.value)), width: Px(156), grow: False }),
				input({ label: "Header value", value: state.header_value, placeholder: "application/json", on_change: |current, event| Gui.update(Workbench.set_header_value(current, event.value)), width: Fill, grow: True }),
			],
		),
		meta("BODY"),
		Gui.textarea({
			label: "Request body",
			value: state.request,
			placeholder: "{\"message\":\"hello\"}",
			on_input: |current, event| Gui.update(Workbench.set_request(current, event.value)),
			width: Fill,
			height: Fill,
			grow: True,
			padding: Theme.inset,
			font_size: Theme.body,
			font_face: Theme.face,
			bg: well_style.bg,
			fg: well_style.fg,
			border_color: well_style.border_color,
			border_width: well_style.border_width,
			radius: well_style.radius,
		}),
		Gui.row(
			{ label: "Send controls", width: Fill, padding: 0, gap: Theme.inset },
			[
				key_cap({ caption: if state.sending "Sending…" else "Send", label: "Send request", enabled: True, on_press: |current, _| Workbench.send(current), bg: Theme.send, hover_bg: Theme.send_hover, active_bg: Theme.send_active }),
				key_cap({ caption: "Retry", label: "Retry request", enabled: !state.sending, on_press: |current, _| Workbench.send(current), bg: Theme.key, hover_bg: Theme.key_hover, active_bg: Theme.key_active }),
				key_cap({ caption: "Dismiss", label: "Dismiss pending response", enabled: state.sending, on_press: |current, _| Workbench.cancel(current), bg: Theme.key, hover_bg: Theme.key_hover, active_bg: Theme.key_active }),
			],
		),
	],
)

readout = |props| Gui.textarea({
	label: props.label,
	value: props.value,
	placeholder: props.placeholder,
	read_only: True,
	on_input: |_, _| Gui.none,
	width: Fill,
	height: props.height,
	grow: props.grow,
	padding: Theme.inset,
	font_size: Theme.body,
	font_face: Theme.face,
	bg: well_style.bg,
	fg: well_style.fg,
	border_color: well_style.border_color,
	border_width: well_style.border_width,
	radius: well_style.radius,
})

## The response side is a readout, not a form: nothing here is editable, the
## status line is the one piece of type larger than body, and the signal colour
## appears only once the bench actually has a reply to show.
response_side = |state| {
	answered = !Str.is_empty(state.response_headers) or state.response_header_count > 0
	Gui.col(
		{ label: "Response readout", width: Fill, height: Fill, grow: True, padding: 10, gap: 8, bg: Theme.ground },
		[
			Gui.row(
				{ label: "Response status", width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[
					Gui.row(
						{ padding: 0, gap: 0, fg: if answered Theme.signal else Theme.dim, font_size: Theme.readout, font_face: Theme.face },
						[Gui.text(state.response_status)],
					),
					trailing_meta("${state.response_bytes.to_str()} B"),
				],
			),
			Gui.row(
				{ width: Fill, padding: 0, gap: Theme.inset, align: Center },
				[meta("Response headers: ${state.response_header_count.to_str()}"), trailing_meta(if state.sending "in flight" else "at rest")],
			),
			readout({ label: "Response headers", value: state.response_headers, placeholder: "headers appear here", height: Px(112), grow: False }),
			meta("BODY"),
			readout({ label: "Response body", value: state.response, placeholder: "the reply body appears here", height: Fill, grow: True }),
		],
	)
}

header = |state| Gui.row(
	{
		label: "Workbench header",
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
		Gui.text("HTTP WORKBENCH"),
		divider,
		meta("one granted origin"),
		divider,
		trailing_meta("req ${state.next_id.to_str()}"),
	],
)

render : Workbench.State -> Gui.Elem(Workbench.State)
render = |state| Gui.col(
	{
		label: "HTTP workbench",
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
		authority_bar(state),
		error_band(state),
		Gui.row(
			{ label: "Bench", width: Fill, height: Fill, grow: True, padding: 0, gap: 0 },
			[request_side(state), response_side(state)],
		),
	],
)
