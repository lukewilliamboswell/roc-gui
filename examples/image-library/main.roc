app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Files
import pf.Layout
import pf.Program exposing [Program]

Picture : { bytes : List(U8), format : Elem.ImageFormat, name : Str }

View : [Empty, Folder({ directory : Files.Dir.Read, entries : List(Files.Entry) })]

Status : [Busy(U64), Failed(Str), Ready]

State : { next_request : U64, picture : [None, Some(Picture)], status : Status, view : View }

format_for : Str -> Try(Elem.ImageFormat, [Unsupported])
format_for = |name| if name.ends_with(".png") {
	Ok(Png)
} else if name.ends_with(".jpg") or name.ends_with(".jpeg") {
	Ok(Jpeg)
} else if name.ends_with(".gif") {
	Ok(Gif)
} else if name.ends_with(".webp") {
	Ok(Webp)
} else if name.ends_with(".svg") {
	Ok(Svg)
} else if name.ends_with(".bmp") {
	Ok(Bmp)
} else if name.ends_with(".tif") or name.ends_with(".tiff") {
	Ok(Tiff)
} else {
	Err(Unsupported)
}

pick = |state| {
	id = state.next_request
	Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match Files.pick_directory!({}) {
			Ok(Chosen(selection)) => match Files.Dir.list!(selection.directory) {
				Ok(entries) => Picked({ directory: selection.directory, entries })
				Err(_) => PickFailed
			}
			Ok(Canceled) => PickCanceled
			Err(_) => PickFailed
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				Picked(folder) => Action.update({ ..latest, view: Folder(folder), status: Ready })
				PickCanceled => Action.update({ ..latest, status: Ready })
				PickFailed => Action.update({ ..latest, status: Failed("Could not open the image folder") })
			}
			_ => Action.none
		},
	})
}

open_image : State, Files.Dir.Read, Str -> Action.Action(State)
open_image = |state, directory, name| match format_for(name) {
	Err(_) => Action.update({ ..state, status: Failed("Unsupported image format") })
	Ok(format) => {
		id = state.next_request
		Action.task({
			pending: { ..state, next_request: id + 1, status: Busy(id) },
			run: || Files.Dir.read!(directory, name),
			resolve: |latest, result| match latest.status {
				Busy(active) if active == id => match result {
					Ok(bytes) => Action.update({ ..latest, picture: Some({ bytes, format, name }), status: Ready })
					Err(_) => Action.update({ ..latest, status: Failed("Could not read the selected image") })
				}
				_ => Action.none
			},
		})
	}
}

render : State -> Elem(State)
render = |state| {
	entries = match state.view {
		Empty => []
		Folder(folder) => folder.entries.keep_if(|entry| entry.kind == File).map(|entry| Elem.button({ label: entry.name, name: "Open image ${entry.name}", on_press: |current, _| open_image(current, folder.directory, entry.name) }))
	}
	viewer = match state.picture {
		None => Elem.panel(Elem.PanelProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True }, [Elem.text("Choose an image")])
		Some(picture) => Elem.panel(Elem.PanelProps.{ label: "Image viewer", width: Fill, height: Fill, grow: True }, [Elem.text(picture.name), Elem.image(Elem.ImageProps.{ label: "Selected image", bytes: picture.bytes, format: picture.format, width: Fill, height: Fill, grow: True })])
	}
	status = match state.status {
		Ready => []
		Busy(_) => [Elem.text("Loading…")]
		Failed(message) => [Elem.panel(Elem.PanelProps.{ label: "Image error", width: Fill }, [Elem.text(message)])]
	}
	Layout.col(Elem.ColProps.{ label: "Image library", width: Fill, height: Fill, grow: True, padding: 20 }, [Elem.text("Image Library"), Elem.button({ label: "Choose image folder", name: "Choose image folder", on_press: |current, _| pick(current) })].concat(status).concat([Layout.row(Elem.RowProps.{ width: Fill, height: Fill, grow: True }, [Elem.scroll(Elem.ScrollProps.{ name: "Image files", content: Layout.col(Elem.ColProps.{ width: Px(220) }, entries) }), viewer])]))
}

main : Program(State)
main = Program.run({ init: { next_request: 0, picture: None, status: Ready, view: Empty }, render, window: { title: "Image Library", width: 960, height: 680 } })
