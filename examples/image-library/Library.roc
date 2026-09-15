import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import Gallery
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

item_rows = |items| {
	var $key = 0
	var $rows = []
	for item in items {
		key = $key
		content = match item {
			Failed(failure) => Elem.text("${failure.name} — ${failure.reason}")
			Ready(asset) => Elem.row(Elem.RowProps.{ label: "Image ${asset.name}", gap: 8 }, [Elem.image(Elem.ImageProps.{ label: "Thumbnail ${asset.name}", bytes: asset.bytes, format: asset.format, fit: Cover, width: Px(72), height: Px(54) }), Elem.action_button(Elem.ActionButtonProps.{ caption: asset.name, label: "View image ${asset.name}", on_press: |current, _| Action.update({ ..current, selected: Some(asset) }) })])
		}
		$rows = $rows.append(Elem.VirtualListItem.{ key, content })
		$key = key + 1
	}
	$rows
}

viewer = |state| match state.selected {
	None => Elem.panel(Elem.PanelProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True }, [Elem.text("Choose an image from the gallery")])
	Some(asset) => Elem.panel(Elem.PanelProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True }, [Elem.text(asset.name), Elem.text("${asset.width.to_str()} × ${asset.height.to_str()} pixels; ${asset.bytes.len().to_str()} encoded bytes"), Elem.row(Elem.RowProps.{ label: "Image transform controls", gap: 8 }, [Elem.action_button(Elem.ActionButtonProps.{ caption: "Fit", label: "Fit image", on_press: |current, _| Action.update({ ..current, transform: { ..current.transform, fit: Contain } }) }), Elem.action_button(Elem.ActionButtonProps.{ caption: "Fill", label: "Fill image bounds", on_press: |current, _| Action.update({ ..current, transform: { ..current.transform, fit: Cover } }) }), Elem.action_button(Elem.ActionButtonProps.{ caption: "Actual", label: "Show actual image size", on_press: |current, _| Action.update({ ..current, transform: { ..current.transform, fit: None } }) }), Elem.checkbox(Elem.CheckboxProps.{ label: "Grayscale preview", checked: state.transform.grayscale, on_change: |current, event| Action.update({ ..current, transform: { ..current.transform, grayscale: event.checked } }) })]), Elem.text("View: ${Viewer.fit_label(state.transform.fit)}"), Viewer.render_image(asset, state.transform)])
}

render = |state| {
	gallery = match state.scan {
		None => Elem.panel(Elem.PanelProps.{ label: "Gallery", width: Px(320), height: Fill }, [Elem.text("No folder open")])
		Some(scan) => {
			visible = Gallery.visible(scan.items, state.filter)
			Elem.col(Elem.ColProps.{ label: "Gallery", width: Px(320), height: Fill, gap: 8 }, [Elem.text_input(Elem.TextInputProps.{ label: "Filter images", value: state.filter, on_change: |current, event| Action.update({ ..current, filter: event.value }), on_submit: |current, _| Action.update(current), width: Fill }), Elem.text("${visible.len().to_str()} of ${scan.items.len().to_str()} entries"), Elem.virtual_list(Elem.VirtualListProps.{ name: "Image thumbnails", row_height: 68, items: item_rows(visible) })])
		}
	}
	status = match state.status { Ready => [], Busy(_) => [Elem.text("Scanning images…")], Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Image error", width: Fill }, [Elem.text(message)])] }
	Elem.col(Elem.ColProps.{ label: "Image library", width: Fill, height: Fill, grow: True, padding: 20, gap: 12 }, [Elem.text("Image Library"), Elem.action_button(Elem.ActionButtonProps.{ caption: "Open folder", label: "Open image folder", on_press: |current, _| pick(current) })].concat(status).concat([Elem.row(Elem.RowProps.{ label: "Library workspace", width: Fill, height: Fill, grow: True, gap: 12 }, [gallery, viewer(state)])]))
}
