import pf.Gui
import Gallery
import Theme
import Viewer

## One icon, a few hundred bytes, so it belongs in the executable rather than in
## an asset store: a compile-time file import needs no capability at all.
import "icons/unreadable.svg" as unreadable_glyph : List(U8)

Library := [].{
	State : State

	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Gui.Access -> State
	init = |access| { access, filter: "", next_request: 0, scan: None, selected: None, status: Ready, transform: Viewer.initial }
	render : State -> Gui.Elem(State)
	render = render
}

Status : [Busy(U64), Failed({ detail : Str, headline : Str }), Ready]

State : { access : Gui.Access, filter : Str, next_request : U64, scan : [None, Some(Gallery.Scan)], selected : [None, Some(Gallery.Asset)], status : Status, transform : Viewer.Transform }

pick = |state| {
	id = state.next_request
	Gui.Action.task({
		pending: { ..state, next_request: id + 1, status: Busy(id) },
		run: || match state.access.pick_directory!() {
			Ok(Chosen(selection)) => match selection.directory.list!() {
				Ok(entries) => Scanned(Gallery.scan!(selection.directory, entries))
				Err(_) => ScanFailed
			}
			Ok(Canceled) => ScanCanceled
			Err(_) => ScanDenied
		},
		resolve: |latest, result| match latest.status {
			Busy(active) if active == id => match result {
				Scanned(scan) => Gui.Action.update({ ..latest, scan: Some(scan), selected: None, status: Ready })
				ScanCanceled => Gui.Action.update({ ..latest, status: Ready })

				## A refusal is a state, not an error string. It says what
				## happened, what it means for what is on screen, and what the
				## person can do about it — and the one thing they can do is
				## the button that is already in the header, so the band points
				## at it rather than growing a second one.
				ScanDenied => Gui.Action.update({ ..latest, status: Failed({ headline: "No folder was opened", detail: "Access to a folder was not granted, so nothing was read. Nothing already open has changed. Press Open folder to choose again." }) })
				ScanFailed => Gui.Action.update({ ..latest, status: Failed({ headline: "That folder could not be read", detail: "The folder was granted but could not be listed. Press Open folder to choose another." }) })
			}
			_ => Gui.Action.none
		},
	})
}

## Secondary text: soft grey, one step down in size, never outlined.
quiet_text = |label, caption| Gui.row(
	{ label, padding: 0, gap: 0, fg: Theme.muted, font_size: Theme.small },
	[Gui.text(caption)],
)

## One of a set of mutually exclusive views, which says whether it is the view
## in force. A separate line reading "View: Fit" beside three buttons named Fit,
## Fill and Actual is an icon beside its own label: it says nothing the controls
## cannot say themselves, and it says it in a place the eye has to travel to.
##
## The state is in the accessible name as well as in the fill, because the
## platform's action button has no pressed state to expose, and a person using
## a screen reader is owed the same fact as a person looking at the colour.
view_button = |caption, label, current, on_press| Gui.button({
	caption,
	label: if current "${label}, current view" else label,
	on_press,
	padding: 12,
	font_size: Theme.body,
	radius: Theme.control_radius,
	bg: if current Theme.accent else Theme.quiet,
	hover_bg: if current Theme.accent_hover else Theme.quiet_hover,
	active_bg: if current Theme.accent_active else Theme.quiet_active,
	fg: if current Theme.on_accent else Theme.ink,
})

## Which row is in the viewer, by name. The gallery and the viewer hold the
## same asset, so the name is enough to point one at the other, and nothing has
## to be kept in step.
chosen_name_of = |state| match state.selected {
	Some(asset) => asset.name
	None => ""
}

item_rows = |items, chosen_name| {
	var $key = 0
	var $rows = []
	for item in items {
		key = $key
		content = match item {

			## An entry with no picture still occupies a picture's place, so the
			## column of thumbnails stays a column. The glyph says what the row
			## lacks; the sentence beside it says why.
			Failed(failure) => Gui.row(
				{ label: "Failed entry ${failure.name}", gap: Theme.within, padding: 0, align: Center },
				[
					Gui.row(
						{ label: "Unreadable ${failure.name}", width: Px(Theme.thumbnail), height: Px(Theme.thumbnail), min_width: Px(Theme.thumbnail), min_height: Px(Theme.thumbnail), padding: 0, gap: 0, bg: Theme.quiet_hover, radius: Theme.media_radius, align: Center, justify: Center },
						[Gui.image({ label: "Unreadable image", bytes: unreadable_glyph, format: Svg, width: Px(28), height: Px(28), min_width: Px(28), min_height: Px(28) })],
					),
					quiet_text("Failed entry text ${failure.name}", "${failure.name} — ${failure.reason}"),
				],
			)

			## A thumbnail is square, and the row says so rather than leaving
			## its height to whatever the row happens to be. It is still drawn
			## exactly this square: the declared box is authoritative and `fit`
			## maps the decoded pixels into it, which
			## examples/image-library/specs/window-gallery.scm asserts from real
			## laid-out geometry rather than leaving to a screenshot.
			Ready(asset) => Gui.row(
				{ label: "Image ${asset.name}", gap: Theme.within, padding: 0, align: Center },
				[
					Gui.image({ label: "Thumbnail ${asset.name}", bytes: asset.bytes, format: asset.format, fit: Cover, width: Px(Theme.thumbnail), height: Px(Theme.thumbnail), min_width: Px(Theme.thumbnail), min_height: Px(Theme.thumbnail), radius: Theme.media_radius }),
					Gui.button({ caption: asset.name, label: "View image ${asset.name}", on_press: |current, _| Gui.Action.update({ ..current, selected: Some(asset) }), width: Px(196), height: Px(Theme.thumbnail), padding: 10, font_size: Theme.body, radius: Theme.control_radius, bg: if chosen_name == asset.name Theme.chosen else Theme.quiet, hover_bg: Theme.quiet_hover, active_bg: Theme.quiet_active, fg: Theme.ink, overflow_x: Clip }),
				],
			)
		}
		$rows = $rows.append({ key, content })
		$key = key + 1
	}
	$rows
}

viewer_controls = |state| Gui.row(
	{ label: "Image transform controls", gap: 12, padding: 0 },
	[
		view_button("Fit", "Fit image", state.transform.fit == Contain, |current, _| Gui.Action.update({ ..current, transform: { ..current.transform, fit: Contain } })),
		view_button("Fill", "Fill image bounds", state.transform.fit == Cover, |current, _| Gui.Action.update({ ..current, transform: { ..current.transform, fit: Cover } })),
		view_button("Actual", "Show actual image size", state.transform.fit == None, |current, _| Gui.Action.update({ ..current, transform: { ..current.transform, fit: None } })),
		Gui.checkbox({ label: "Grayscale preview", checked: state.transform.grayscale, padding: 12, gap: 10, font_size: Theme.body, fg: Theme.ink, box_bg: Theme.card, box_checked_bg: Theme.accent, box_border: Theme.quiet_active, mark_color: Theme.on_accent, on_change: |current, event| Gui.Action.update({ ..current, transform: { ..current.transform, grayscale: event.checked } }) }),
	],
)

viewer = |state| match state.selected {
	None => Gui.col(
		{ label: "Image viewer", width: Fill, height: Fill, grow: True, gap: Theme.within, padding: 0 },
		[quiet_text("Viewer placeholder", "Choose an image from the gallery")],
	)
	Some(asset) => Gui.col(
		{ label: "Image viewer", width: Fill, height: Fill, grow: True, gap: Theme.within, padding: 0 },
		[
			Gui.row({ label: "Image title", padding: 0, gap: 0, font_size: Theme.heading, fg: Theme.ink }, [Gui.text(asset.name)]),
			Viewer.render_image(asset, state.transform),
			quiet_text("Image metadata", "${asset.width.to_str()} × ${asset.height.to_str()} pixels; ${asset.bytes.len().to_str()} encoded bytes"),
			viewer_controls(state),
		],
	)
}

gallery = |state| match state.scan {
	None => Gui.col(
		{ label: "Gallery", width: Px(320), height: Fill, gap: Theme.within, padding: 0 },
		[quiet_text("Gallery placeholder", "No folder open")],
	)
	Some(scan) => {
		visible = Gallery.visible(scan.items, state.filter)
		Gui.col(
			{ label: "Gallery", width: Px(320), height: Fill, gap: Theme.within, padding: 0 },
			[
				Gui.text_input({ label: "Filter images", value: state.filter, placeholder: "Search this folder", on_change: |current, event| Gui.Action.update({ ..current, filter: event.value }), on_submit: |_, _| Gui.Action.none, width: Fill, height: Px(44), padding: 14, font_size: Theme.body, bg: Theme.card, fg: Theme.ink, border_width: 0, radius: Theme.control_radius }),
				quiet_text("Gallery count", "${visible.len().to_str()} of ${scan.items.len().to_str()} entries"),
				Gui.virtual_list({ label: "Image thumbnails", row_height: Theme.row_height, items: item_rows(visible, chosen_name_of(state)) }),
			],
		)
	}
}

status_band = |state| match state.status {
	Ready => []
	Busy(_) => [quiet_text("Scan status", "Scanning images…")]
	Failed(failure) => [
		Gui.col(
			{ label: "Image error", width: Fill, padding: 20, gap: 8, bg: Theme.alarm, fg: Theme.alarm_ink, border_width: 0, radius: Theme.control_radius, font_size: Theme.body },
			[
				Gui.row({ label: "Error headline", padding: 0, gap: 0, fg: Theme.alarm_ink, font_size: Theme.body, font_weight: 600 }, [Gui.text(failure.headline)]),
				Gui.row({ label: "Error detail", padding: 0, gap: 0, fg: Theme.alarm_ink, font_size: Theme.small }, [Gui.text(failure.detail)]),
			],
		),
	]
}

header = Gui.row(
	{ label: "Library header", width: Fill, gap: Theme.between, padding: 0, align: Center },
	[
		Gui.row({ label: "Library title", grow: True, padding: 0, gap: 0, font_size: Theme.title, fg: Theme.ink }, [Gui.text("Image Library")]),
		Gui.button({
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

render = |state| Gui.col(
	{ label: "Image library", width: Fill, height: Fill, grow: True, padding: Theme.margin, gap: Theme.between, bg: Theme.paper, fg: Theme.ink, font_size: Theme.body },
	[header]
		.concat(status_band(state))
		.concat([
			Gui.row(
				{ label: "Library workspace", width: Fill, height: Fill, grow: True, gap: Theme.between, padding: 0 },
				[gallery(state), viewer(state)],
			),
		]),
)
