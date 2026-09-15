import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import Gallery
import Theme
import Viewer

Library := [].{
	State : State
	init : State
	init = { filter: "", next_request: 0, scan: None, selected: None, status: Ready, transform: Viewer.initial }
	render : State -> Elem(State)
	render = render
}

Status : [Busy(U64), Failed(Str), Ready]
State : { filter : Str, next_request : U64, scan : [None, Some(Gallery.Scan)], selected : [None, Some(Gallery.Asset)], status : Status, transform : Viewer.Transform }

pick = |state| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Files.pick_directory!({}) {
			Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) { Ok(entries) => Scanned(Gallery.scan!(selection.directory, entries)), Err(_) => ScanFailed }
			Ok(Canceled) => ScanCanceled
			Err(_) => ScanDenied
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result { Scanned(scan) => Action.update({ ..latest, scan: Some(scan), selected: None, status: Ready }), ScanCanceled => Action.update({ ..latest, status: Ready }), ScanDenied => Action.update({ ..latest, status: Failed("Folder access was not granted") }), ScanFailed => Action.update({ ..latest, status: Failed("Could not scan the image folder") }) }
			_ => Action.none
		},
	})
}

## Secondary text: soft grey, one step down in size, never outlined.
quiet_text = |label, caption| Elem.row(
	Elem.RowProps.{ label, padding: 0, gap: 0, fg: Theme.muted, font_size: Theme.small },
	[Elem.text(caption)],
)

## A control that shows nothing at rest and warms under the pointer.
quiet_button = |caption, label, on_press| Elem.action_button(Elem.ActionButtonProps.{
	caption,
	label,
	on_press,
	padding: 12,
	font_size: Theme.body,
	radius: Theme.control_radius,
	bg: Theme.quiet,
	hover_bg: Theme.quiet_hover,
	active_bg: Theme.quiet_active,
	fg: Theme.ink,
})

item_rows = |items| {
	var $key = 0
	var $rows = []
	for item in items {
		key = $key
		content = match item {
			Failed(failure) => quiet_text("Failed entry ${failure.name}", "${failure.name} — ${failure.reason}")
			Ready(asset) => Elem.row(
				Elem.RowProps.{ label: "Image ${asset.name}", gap: Theme.within, padding: 0 },
				[
					Elem.image(Elem.ImageProps.{ label: "Thumbnail ${asset.name}", bytes: asset.bytes, format: asset.format, fit: Cover, width: Px(88), height: Px(88), radius: Theme.media_radius }),
					Elem.action_button(Elem.ActionButtonProps.{ caption: asset.name, label: "View image ${asset.name}", on_press: |current, _| Action.update({ ..current, selected: Some(asset) }), width: Px(196), height: Px(88), padding: 10, font_size: Theme.body, radius: Theme.control_radius, bg: Theme.quiet, hover_bg: Theme.quiet_hover, active_bg: Theme.quiet_active, fg: Theme.ink, overflow_x: Clip }),
				],
			)
		}
		$rows = $rows.append(Elem.VirtualListItem.{ key, content })
		$key = key + 1
	}
	$rows
}

viewer_controls = |state| Elem.row(
	Elem.RowProps.{ label: "Image transform controls", gap: 12, padding: 0 },
	[
		quiet_button("Fit", "Fit image", |current, _| Action.update({ ..current, transform: { ..current.transform, fit: Contain } })),
		quiet_button("Fill", "Fill image bounds", |current, _| Action.update({ ..current, transform: { ..current.transform, fit: Cover } })),
		quiet_button("Actual", "Show actual image size", |current, _| Action.update({ ..current, transform: { ..current.transform, fit: None } })),
		Elem.checkbox(Elem.CheckboxProps.{ label: "Grayscale preview", checked: state.transform.grayscale, padding: 12, gap: 10, font_size: Theme.body, fg: Theme.ink, on_change: |current, event| Action.update({ ..current, transform: { ..current.transform, grayscale: event.checked } }) }),
	],
)

viewer = |state| match state.selected {
	None => Elem.col(
		Elem.ColProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True, gap: Theme.within, padding: 0 },
		[quiet_text("Viewer placeholder", "Choose an image from the gallery")],
	)
	Some(asset) => Elem.col(
		Elem.ColProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True, gap: Theme.within, padding: 0 },
		[
			Elem.row(Elem.RowProps.{ label: "Image title", padding: 0, gap: 0, font_size: Theme.heading, fg: Theme.ink }, [Elem.text(asset.name)]),
			quiet_text("Image metadata", "${asset.width.to_str()} × ${asset.height.to_str()} pixels; ${asset.bytes.len().to_str()} encoded bytes"),
			viewer_controls(state),
			quiet_text("Image view mode", "View: ${Viewer.fit_label(state.transform.fit)}"),
			Viewer.render_image(asset, state.transform),
		],
	)
}

gallery = |state| match state.scan {
	None => Elem.col(
		Elem.ColProps.{ label: "Gallery", width: Px(320), height: Fill, gap: Theme.within, padding: 0 },
		[quiet_text("Gallery placeholder", "No folder open")],
	)
	Some(scan) => {
		visible = Gallery.visible(scan.items, state.filter)
		Elem.col(
			Elem.ColProps.{ label: "Gallery", width: Px(320), height: Fill, gap: Theme.within, padding: 0 },
			[
				Elem.text_input(Elem.TextInputProps.{ label: "Filter images", value: state.filter, placeholder: "Search this folder", on_change: |current, event| Action.update({ ..current, filter: event.value }), on_submit: |current, _| Action.update(current), width: Fill, height: Px(44), padding: 14, font_size: Theme.body, bg: Theme.card, fg: Theme.ink, border_width: 0, radius: Theme.control_radius }),
				quiet_text("Gallery count", "${visible.len().to_str()} of ${scan.items.len().to_str()} entries"),
				Elem.virtual_list(Elem.VirtualListProps.{ name: "Image thumbnails", row_height: Theme.row_height, items: item_rows(visible) }),
			],
		)
	}
}

status_band = |state| match state.status {
	Ready => []
	Busy(_) => [quiet_text("Scan status", "Scanning images…")]
	Failed(message) => [
		Elem.col(
			Elem.ColProps.{ label: "Image error", width: Fill, padding: 20, gap: 0, bg: Theme.alarm, fg: Theme.alarm_ink, border_width: 0, radius: Theme.control_radius, font_size: Theme.body },
			[Elem.text(message)],
		),
	]
}

header = Elem.row(
	Elem.RowProps.{ label: "Library header", width: Fill, gap: Theme.between, padding: 0 },
	[
		Elem.row(Elem.RowProps.{ label: "Library title", padding: 0, gap: 0, font_size: Theme.title, fg: Theme.ink }, [Elem.text("Image Library")]),
		Elem.action_button(Elem.ActionButtonProps.{
			caption: "Open folder",
			label: "Open image folder",
			on_press: |current, _| pick(current),
			padding: 12,
			font_size: Theme.body,
			radius: Theme.control_radius,
			bg: Theme.accent,
			hover_bg: Theme.accent_hover,
			active_bg: Theme.accent_active,
			fg: Theme.on_accent,
		}),
	],
)

render = |state| Elem.col(
	Elem.ColProps.{ label: "Image library", width: Fill, height: Fill, grow: True, padding: Theme.margin, gap: Theme.between, bg: Theme.paper, fg: Theme.ink, font_size: Theme.body },
	[header]
		.concat(status_band(state))
		.concat([
			Elem.row(
				Elem.RowProps.{ label: "Library workspace", width: Fill, height: Fill, grow: True, gap: Theme.between, padding: 0 },
				[gallery(state), viewer(state)],
			),
		]),
)
