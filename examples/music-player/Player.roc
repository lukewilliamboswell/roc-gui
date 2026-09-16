import pf.Action
import pf.Assets
import pf.Audio
import pf.Elem
import pf.Files
import pf.Gui

Player := [].{
	State : State
	init : State
	init = { art: NoArt, chosen: Nothing, generation: 0, library: Empty, playback: Idle, status: "Choose a music folder" }
	render : State -> Elem(State)
	render = render
}

Track : { name : Str }
Library : [Empty, Loaded({ directory : Files.Dir.Read, output : Audio.Output, tracks : List(Track) })]
Playback : [Idle, Active({ index : U64, paused : Bool, track : Audio.Track }), Stopped]

## The cover the sleeve shows. A photograph is too large to pay for in
## executable size, so it is not a compile-time file import: it lives in the
## asset set shipped beside the program and is read through a store.
Art : [NoArt, Cover(List(U8)), NoCover]

## The row a person last asked for. It is not the sounding row: a track is
## chosen the moment it is clicked and only starts once it has loaded, and a
## track that fails to decode stays chosen so the failure has a place to sit.
Chosen : [Nothing, At(U64)]
State : { art : Art, chosen : Chosen, generation : U64, library : Library, playback : Playback, status : Str }

## The asset set this application ships with. The expectation is compared with
## the `roc-assets.manifest` beside the artwork when the store opens, so a
## half-updated or swapped asset set is a failure at open rather than a picture
## that silently will not draw.
art_manifest = { asset_set: "nocturne-art", schema: 1.U32, content_version: 1.U32, content: AnyContent }

## Read the cover the application ships with. Opening a store and reading an
## asset both block on the disk, so both belong in a task's `run` rather than in
## a renderer or an event handler. This is called from the scan's own `run`: the
## sleeve is dressed on the same worker trip that opens the library, so reading
## the artwork costs no second round trip and changes nobody else's sequencing.
##
## Every failure is one answer, `NoCover`, because there is nothing a person can
## do differently about a manifest that disagrees and about a content directory
## that was never provisioned. The reason is not lost: the asset owner's
## counters separate a refused open from a refused read.
read_cover! : {} => Art
read_cover! = |{}| match Assets.open!(Assets.with_manifest(Assets.content_directory, art_manifest)) {
	Err(_) => NoCover
	Ok(store) => match Assets.read!(store, "art/nocturne-cover.jpg") {
		Err(_) => NoCover
		Ok(bytes) => Cover(bytes)
	}
}

is_audio = |name| Str.ends_with(name, ".wav")

audio_error = |err| match err {
	AcquireAudioErr(_) => "Audio output acquisition failed"
	LoadAudioErr(Unsupported) => "Track format is unsupported"
	LoadAudioErr(DecodeFailed) => "Track could not be decoded"
	LoadAudioErr(_) => "Track could not be loaded"
	PlayAudioErr(_) => "Track could not be played"
	PauseAudioErr(_) => "Pause failed"
	SeekAudioErr(_) => "Seek failed"
	StatusAudioErr(_) => "Playback status failed"
	StopAudioErr(_) => "Stop failed"
}

scan = |state| Action.task({
	pending: { ..state, status: "Scanning…" },
	run: || {
		## The cover is read whatever the chooser goes on to answer. A folder a
		## person declined to pick is not a reason for the sleeve to stay bare.
		art = read_cover!({})
		outcome = match Files.pick_directory!() {
			Err(PickDirectoryErr(Unavailable)) => ScanFailed("This system offers no folder chooser")
			Err(_) => ScanFailed("Music folder access was denied")
			Ok(Canceled) => ScanCanceled
			Ok(Chosen(selection)) => match Audio.acquire!() {
				Err(err) => ScanFailed(audio_error(err))
				Ok(output) => match Files.Dir.list!(selection.directory) {
					Err(_) => ScanFailed("Music folder could not be read")
					Ok(entries) => {
						tracks = List.keep_oks(entries, |entry| if entry.kind == File and is_audio(entry.name) { Ok({ name: entry.name }) } else { Err({}) })
						Scanned({ directory: selection.directory, output, tracks })
					}
				}
			}
		}
		{ art, outcome }
	},
	resolve: |latest, result| {
		dressed = { ..latest, art: result.art }
		match result.outcome {
			ScanFailed(message) => Action.update({ ..dressed, status: message })
			ScanCanceled => Action.update({ ..dressed, status: "Folder choice canceled" })
			Scanned(library) => Action.update({ ..dressed, chosen: Nothing, library: Loaded(library), playback: Idle, status: "${U64.to_str(List.len(library.tracks))} tracks" })
		}
	},
})

play_index = |state, library, index| match library.tracks.get(index) {
	Err(_) => Action.update(state)
	Ok(item) => {
		generation = state.generation + 1
		Action.task({
		pending: { ..state, chosen: At(index), generation, status: "Loading ${item.name}…" },
		run: || match Audio.load!(library.output, library.directory, item.name) {
			Err(err) => PlayFailed(generation, audio_error(err))
			Ok(loaded) => match Audio.play!(loaded.track) {
				Err(err) => PlayFailed(generation, audio_error(err))
				Ok(_) => PlayStarted(generation, index, loaded.track)
			}
		},
		resolve: |latest, result| match result {
			PlayFailed(request, message) => if request == latest.generation { Action.update({ ..latest, status: message }) } else { Action.update(latest) }
			PlayStarted(request, started_index, track) => if request == latest.generation { Action.update({ ..latest, playback: Active({ index: started_index, paused: False, track }), status: "Playing ${item.name}" }) } else { Action.task({ pending: latest, run: || Audio.stop!(track), resolve: |current, _| Action.update(current) }) }
		},
	}) }
}

stop = |state| match state.playback {
	Active(current) => Action.task({ pending: { ..state, generation: state.generation + 1, status: "Stopping…" }, run: || Audio.stop!(current.track), resolve: |latest, result| match result { Ok(_) => Action.update({ ..latest, chosen: Nothing, playback: Stopped, status: "Stopped" })
		Err(_) => Action.update({ ..latest, status: "Stop failed" }) } })
	_ => Action.update(state)
}

seek_forward = |state| match state.playback {
	Active(current) => Action.task({ pending: { ..state, status: "Seeking…" }, run: || Audio.seek!(current.track, 100), resolve: |latest, result| match result { Ok(_) => Action.update({ ..latest, status: "Position 100 ms" })
		Err(err) => Action.update({ ..latest, status: audio_error(err) }) } })
	_ => Action.update(state)
}

refresh_status = |state| match state.playback {
	Active(current) => Action.task({ pending: state, run: || Audio.status!(current.track), resolve: |latest, result| match result { Ok(status) => Action.update({ ..latest, status: "Position ${U64.to_str(status.position_ms)} ms" })
		Err(err) => Action.update({ ..latest, status: audio_error(err) }) } })
	_ => Action.update(state)
}

toggle = |state| match state.playback {
	Idle | Stopped => match state.library {
		Empty => Action.update(state)
		Loaded(library) => play_index(state, library, 0)
	}
	Active(current) => if current.paused {
		Action.task({ pending: { ..state, status: "Resuming…" }, run: || Audio.play!(current.track), resolve: |latest, result| match result {
			Ok(_) => Action.update({ ..latest, playback: Active({ ..current, paused: False }), status: "Playing" })
			Err(_) => Action.update({ ..latest, status: "Resume failed" })
		} })
	} else {
		Action.task({ pending: { ..state, status: "Pausing…" }, run: || Audio.pause!(current.track), resolve: |latest, result| match result {
			Ok(_) => Action.update({ ..latest, playback: Active({ ..current, paused: True }), status: "Paused" })
			Err(_) => Action.update({ ..latest, status: "Pause failed" })
		} })
	}
}

## The row Next and Previous step away from. A transport is not inert just
## because nothing is sounding: after a track failed to load, or before anything
## has played, the chosen row is the one a person is standing on, and an empty
## queue starts from the top.
step_origin = |state| match state.playback {
	Active(current) => At(current.index)
	_ => state.chosen
}

## Step from the origin without running off either end of the queue.
step_target = |origin, len, delta| match origin {
	Nothing => if delta < 0 { len - 1 } else { 0 }
	At(index) => if delta < 0 {
		if index == 0 { 0 } else { index - 1 }
	} else if index + 1 >= len { index } else { index + 1 }
}

step = |state, delta| match state.library {
	Empty => Action.update(state)
	Loaded(library) => {
		len = List.len(library.tracks)
		if len == 0 {
			Action.update(state)
		} else {
			next = step_target(step_origin(state), len, delta)
			match state.playback {
				Active(current) => stop_then_play(state, current.track, next)
				_ => play_index(state, library, next)
			}
		}
	}
}

stop_then_play = |state, track, next| Action.task({
	pending: { ..state, generation: state.generation + 1, status: "Changing track…" },
	run: || Audio.stop!(track),
	resolve: |latest, result| match result {
		Err(err) => Action.update({ ..latest, status: audio_error(err) })
		## The old track really has stopped, so the transport stops believing it
		## is sounding. Otherwise a load that then fails leaves a phantom Active
		## row, and the next step walks away from that instead of from the row
		## the person is standing on.
		Ok(_) => match latest.library {
			Empty => Action.update({ ..latest, playback: Stopped })
			Loaded(latest_library) => play_index({ ..latest, playback: Stopped }, latest_library, next)
		}
	},
})


## High-contrast night. A near-black ground, one vivid ember accent reserved
## for the primary transport and the track that is sounding, and pill controls
## whose hover and press colours are always a visible step apart.
ground = Gui.rgb(0x08080b)
surface = Gui.rgb(0x0b0b10)
row_rest = Gui.rgb(0x15151d)
row_hover = Gui.rgb(0x23232f)
row_press = Gui.rgb(0x32323f)
hairline = Gui.rgb(0x20202b)
ink = Gui.rgb(0xf2efec)
muted = Gui.rgb(0x8b8798)
accent = Gui.rgb(0xff4b12)
accent_hot = Gui.rgb(0xff7040)
accent_deep = Gui.rgb(0xc2360b)
accent_tint = Gui.rgb(0x2b1109)
accent_tint_hot = Gui.rgb(0x3a1710)
accent_tint_press = Gui.rgb(0x4a1d13)
on_accent = Gui.rgb(0x0a0a0c)

## A chosen row that is not yet the sounding one is Waiting, which is what makes
## a click visible while the next track loads or after one failed to decode.
active_index = |state| {
	live = match state.playback {
		Active(current) => { index: At(current.index), paused: current.paused }
		_ => { index: Nothing, paused: False }
	}
	mark = |index| if live.paused Held(index) else Sounding(index)
	match state.chosen {
		At(index) => if live.index == At(index) mark(index) else Waiting(index)
		Nothing => match live.index {
			At(index) => mark(index)
			Nothing => Silent
		}
	}
}

track_row = |library, index, track, marker| {
	tone = match marker {
		Sounding(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: accent, border_color: accent, border_width: 1 }
		Held(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: accent_hot, border_color: accent_deep, border_width: 1 }
		Waiting(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: muted, border_color: hairline, border_width: 1 }
		_ => { bg: row_rest, hover_bg: row_hover, active_bg: row_press, fg: ink, border_color: hairline, border_width: 0 }
	}
	Elem.action_button(Elem.ActionButtonProps.{
		caption: track.name,
		label: "Play ${track.name}",
		on_press: |current, _| play_index(current, library, index),
		width: Fill,
		height: Px(38),
		padding: 12,
		radius: 10,
		font_size: 14,
		bg: tone.bg,
		hover_bg: tone.hover_bg,
		active_bg: tone.active_bg,
		fg: tone.fg,
		border_color: tone.border_color,
		border_width: tone.border_width,
	})
}

track_items = |state, library| {
	marker = active_index(state)
	var $index = 0
	var $items = []
	for track in library.tracks {
		index = $index
		$items = $items.append(Elem.VirtualListItem.{ key: index, content: track_row(library, index, track, marker) })
		$index = index + 1
	}
	$items
}

transport = |caption, name, press| Elem.action_button(Elem.ActionButtonProps.{
	caption,
	label: name,
	on_press: press,
	padding: 18,
	padding_top: Px(10),
	padding_bottom: Px(10),
	radius: 24,
	font_size: 15,
	bg: Gui.rgb(0x15151d),
	hover_bg: Gui.rgb(0x23232f),
	active_bg: Gui.rgb(0x32323f),
	fg: ink,
	border_color: hairline,
	border_width: 1,
})

primary_transport = |caption| Elem.action_button(Elem.ActionButtonProps.{
	caption,
	label: "Toggle playback",
	on_press: |current, _| toggle(current),
	width: Px(168),
	padding: 18,
	padding_top: Px(10),
	padding_bottom: Px(10),
	radius: 24,
	font_size: 16,
	font_weight: 600,
	bg: accent,
	hover_bg: accent_hot,
	active_bg: accent_deep,
	fg: on_accent,
})

## The sleeve keeps its square whatever it holds, so the status line does not
## move when the cover arrives. Empty, it is the same dark tile a track row
## rests on; it never takes the accent, which belongs to the sounding track and
## the primary transport alone.
sleeve_size = 76.U32
empty_sleeve = Elem.row(Elem.RowProps.{ label: "Sleeve", width: Px(sleeve_size), height: Px(sleeve_size), min_width: Px(sleeve_size), min_height: Px(sleeve_size), padding: 0, gap: 0, bg: row_rest, border_color: hairline, border_width: 1, radius: 12 }, [])

sleeve = |art| match art {
	Cover(bytes) => Elem.image(Elem.ImageProps.{ label: "Cover art", bytes, format: Jpeg, fit: Cover, width: Px(sleeve_size), height: Px(sleeve_size), min_width: Px(sleeve_size), min_height: Px(sleeve_size), radius: 12 })
	NoArt | NoCover => empty_sleeve
}

## A missing cover is said once, quietly, and only after the read was tried.
## An empty square with no explanation is a defect a person cannot report.
sleeve_caption = |art| match art {
	NoCover => [Elem.row(Elem.RowProps.{ label: "Cover art status", padding: 0, gap: 0, fg: muted, font_size: 13, font_weight: 400 }, [Elem.text("Cover art unavailable")])]
	NoArt | Cover(_) => []
}

toggle_caption = |state| match state.playback {
	Active(current) => if current.paused "Resume" else "Pause"
	_ => "Play"
}

render : State -> Elem(State)
render = |state| {
	library_view = match state.library {
		Empty => Elem.panel(Elem.PanelProps.{ label: "Music library", grow: True, width: Fill, padding: 28, bg: surface, border_color: hairline, radius: 16, fg: muted, font_size: 15 }, [
			Elem.text("No folder chosen yet."),
			Elem.text("Grant a music folder to build the queue."),
		])
		Loaded(library) => Elem.panel(Elem.PanelProps.{ label: "Music library", grow: True, width: Fill, padding: 10, gap: 0, bg: surface, border_color: hairline, radius: 16, overflow_y: Clip }, [
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Tracks", row_height: 44, items: track_items(state, library) }),
		])
	}
	Elem.col(Elem.ColProps.{ label: "Music player", width: Fill, height: Fill, grow: True, padding: 26, gap: 18, bg: ground, fg: ink, font_size: 15 }, [
		Elem.row(Elem.RowProps.{ label: "Header", width: Fill, gap: 16 }, [
			Elem.row(Elem.RowProps.{ label: "Wordmark", grow: True, fg: accent, font_size: 28, font_weight: 700 }, [Elem.text("NOCTURNE")]),
			Elem.action_button(Elem.ActionButtonProps.{
				caption: "Choose folder",
				label: "Choose music folder",
				on_press: |current, _| scan(current),
				height: Px(40),
				padding: 18,
				radius: 20,
				font_size: 14,
				bg: ground,
				hover_bg: accent_tint,
				active_bg: accent_tint_press,
				fg: accent,
				border_color: accent_deep,
				border_width: 1,
			}),
		]),
		Elem.panel(Elem.PanelProps.{ label: "Playback status", width: Fill, padding: 18, gap: 18, radius: 16, bg: surface, border_color: hairline, fg: muted, font_size: 13, font_weight: 600 }, [
			Elem.row(Elem.RowProps.{ label: "Now playing", width: Fill, gap: 18, padding: 0, align: Center }, [
				sleeve(state.art),
				Elem.col(
					Elem.ColProps.{ label: "Now playing text", grow: True, gap: 6, padding: 0 },
					[
						Elem.text("NOW PLAYING"),
						Elem.row(Elem.RowProps.{ label: "Status line", padding: 0, gap: 0, fg: ink, font_size: 19, font_weight: 400 }, [Elem.text(state.status)]),
					].concat(sleeve_caption(state.art)),
				),
			]),
		]),
		library_view,
		Elem.row(Elem.RowProps.{ label: "Playback controls", width: Fill, gap: 12 }, [
			transport("Previous", "Previous track", |current, _| step(current, -1)),
			primary_transport(toggle_caption(state)),
			transport("Next", "Next track", |current, _| step(current, 1)),
			transport("Stop", "Stop playback", |current, _| stop(current)),
			transport("+100 ms", "Seek forward", |current, _| seek_forward(current)),
			transport("Refresh", "Refresh playback status", |current, _| refresh_status(current)),
		]),
	])
}
