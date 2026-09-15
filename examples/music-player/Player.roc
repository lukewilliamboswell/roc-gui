import pf.Action
import pf.Audio
import pf.Elem exposing [Elem]
import pf.Files
import pf.Gui

Player := [].{
	State : State
	init : State
	init = { generation: 0, library: Empty, playback: Idle, status: "Choose a music folder" }
	render : State -> Elem(State)
	render = render
}

Track : { name : Str }
Library : [Empty, Loaded({ directory : Files.Dir.Read, output : Audio.Output, tracks : List(Track) })]
Playback : [Idle, Paused({ index : U64, track : Audio.Track }), Playing({ index : U64, track : Audio.Track }), Stopped]
State : { generation : U64, library : Library, playback : Playback, status : Str }

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
	run: || match Files.pick_directory!({}) {
		Err(_) => ScanFailed("Music folder access was denied")
		Ok(Canceled) => ScanCanceled
		Ok(Chosen(selection)) => match Audio.acquire!({}) {
			Err(err) => ScanFailed(audio_error(err))
			Ok(output) => match Files.Dir.list!(selection.directory) {
				Err(_) => ScanFailed("Music folder could not be read")
				Ok(entries) => {
					tracks = List.keep_oks(entries, |entry| if entry.kind == File and is_audio(entry.name) { Ok({ name: entry.name }) } else { Err({}) })
					Scanned({ directory: selection.directory, output, tracks })
				}
			}
		}
	},
	resolve: |latest, result| match result {
		ScanFailed(message) => Action.update({ ..latest, status: message })
		ScanCanceled => Action.update({ ..latest, status: "Folder choice canceled" })
		Scanned(library) => Action.update({ ..latest, library: Loaded(library), playback: Idle, status: "${U64.to_str(List.len(library.tracks))} tracks" })
	},
})

play_index = |state, library, index| match library.tracks.get(index) {
	Err(_) => Action.update(state)
	Ok(item) => {
		generation = state.generation + 1
		Action.task({
		pending: { ..state, generation, status: "Loading ${item.name}…" },
		run: || match Audio.load!(library.output, library.directory, item.name) {
			Err(err) => PlayFailed(generation, audio_error(err))
			Ok(loaded) => match Audio.play!(loaded.track) {
				Err(err) => PlayFailed(generation, audio_error(err))
				Ok(_) => PlayStarted(generation, index, loaded.track)
			}
		},
		resolve: |latest, result| match result {
			PlayFailed(request, message) => if request == latest.generation { Action.update({ ..latest, status: message }) } else { Action.update(latest) }
			PlayStarted(request, started_index, track) => if request == latest.generation { Action.update({ ..latest, playback: Playing({ index: started_index, track }), status: "Playing ${item.name}" }) } else { Action.task({ pending: latest, run: || Audio.stop!(track), resolve: |current, _| Action.update(current) }) }
		},
	}) }
}

stop = |state| match state.playback {
	Playing(current) | Paused(current) => Action.task({ pending: { ..state, generation: state.generation + 1, status: "Stopping…" }, run: || Audio.stop!(current.track), resolve: |latest, result| match result { Ok(_) => Action.update({ ..latest, playback: Stopped, status: "Stopped" })
		Err(_) => Action.update({ ..latest, status: "Stop failed" }) } })
	_ => Action.update(state)
}

seek_forward = |state| match state.playback {
	Playing(current) | Paused(current) => Action.task({ pending: { ..state, status: "Seeking…" }, run: || Audio.seek!(current.track, 100), resolve: |latest, result| match result { Ok(_) => Action.update({ ..latest, status: "Position 100 ms" })
		Err(err) => Action.update({ ..latest, status: audio_error(err) }) } })
	_ => Action.update(state)
}

refresh_status = |state| match state.playback {
	Playing(current) | Paused(current) => Action.task({ pending: state, run: || Audio.status!(current.track), resolve: |latest, result| match result { Ok(status) => Action.update({ ..latest, status: "Position ${U64.to_str(status.position_ms)} ms" })
		Err(err) => Action.update({ ..latest, status: audio_error(err) }) } })
	_ => Action.update(state)
}

toggle = |state| match state.playback {
	Idle | Stopped => match state.library {
		Empty => Action.update(state)
		Loaded(library) => play_index(state, library, 0)
	}
	Playing(current) => Action.task({ pending: { ..state, status: "Pausing…" }, run: || Audio.pause!(current.track), resolve: |latest, result| match result {
		Ok(_) => Action.update({ ..latest, playback: Paused(current), status: "Paused" })
		Err(_) => Action.update({ ..latest, status: "Pause failed" })
	} })
	Paused(current) => Action.task({ pending: { ..state, status: "Resuming…" }, run: || Audio.play!(current.track), resolve: |latest, result| match result {
		Ok(_) => Action.update({ ..latest, playback: Playing(current), status: "Playing" })
		Err(_) => Action.update({ ..latest, status: "Resume failed" })
	} })
}

step = |state, delta| match (state.library, state.playback) {
	(Loaded(library), Playing(current)) | (Loaded(library), Paused(current)) => {
		len = List.len(library.tracks)
		next = if delta < 0 { if current.index == 0 0 else current.index - 1 } else if current.index + 1 >= len current.index else current.index + 1
		Action.task({
			pending: { ..state, generation: state.generation + 1, status: "Changing track…" },
			run: || Audio.stop!(current.track),
			resolve: |latest, result| match result {
				Err(err) => Action.update({ ..latest, status: audio_error(err) })
				Ok(_) => match latest.library {
					Empty => Action.update(latest)
					Loaded(latest_library) => play_index(latest, latest_library, next)
				}
			},
		})
	}
	_ => Action.update(state)
}


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

active_index = |state| match state.playback {
	Playing(current) => Sounding(current.index)
	Paused(current) => Held(current.index)
	_ => Silent
}

track_row = |library, index, track, marker| {
	tone = match marker {
		Sounding(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: accent, border_color: accent, border_width: 1 }
		Held(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: accent_hot, border_color: accent_deep, border_width: 1 }
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
	height: Px(48),
	padding: 18,
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
	height: Px(48),
	padding: 18,
	radius: 24,
	font_size: 16,
	bg: accent,
	hover_bg: accent_hot,
	active_bg: accent_deep,
	fg: on_accent,
})

toggle_caption = |state| match state.playback {
	Playing(_) => "Pause"
	Paused(_) => "Resume"
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
			Elem.row(Elem.RowProps.{ label: "Wordmark", grow: True, fg: accent, font_size: 28 }, [Elem.text("NOCTURNE")]),
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
		Elem.panel(Elem.PanelProps.{ label: "Playback status", width: Fill, padding: 18, radius: 16, bg: surface, border_color: hairline, fg: muted, font_size: 13 }, [
			Elem.text("NOW PLAYING"),
			Elem.row(Elem.RowProps.{ label: "Status line", fg: ink, font_size: 19 }, [Elem.text(state.status)]),
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
