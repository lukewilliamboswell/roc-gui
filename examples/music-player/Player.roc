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

step! = |state, delta| match (state.library, state.playback) {
	(Loaded(library), Playing(current)) | (Loaded(library), Paused(current)) => {
		len = List.len(library.tracks)
		next = if delta < 0 { if current.index == 0 0 else current.index - 1 } else if current.index + 1 >= len current.index else current.index + 1
		_ = Audio.stop!(current.track)
		play_index(state, library, next)
	}
	_ => Action.update(state)
}

track_items = |_state, library| {
	var $index = 0
	var $items = []
	for track in library.tracks {
		index = $index
		$items = $items.append(Elem.VirtualListItem.{ key: index, content: Elem.action_button(Elem.ActionButtonProps.{ caption: track.name, label: "Play ${track.name}", on_press: |current, _| play_index(current, library, index) }) })
		$index = index + 1
	}
	$items
}

render : State -> Elem(State)
render = |state| {
	library_view = match state.library {
		Empty => Elem.panel(Elem.PanelProps.{ label: "Music library", grow: True, width: Fill }, [Elem.text("No folder scanned")])
		Loaded(library) => Elem.virtual_list(Elem.VirtualListProps.{ name: "Tracks", row_height: 42, items: track_items(state, library) })
	}
	Elem.col(Elem.ColProps.{ label: "Music player", width: Fill, height: Fill, grow: True, padding: 24, gap: 16 }, [
		Elem.text("Music Player"),
		Elem.row(Elem.RowProps.{ label: "Library actions" }, [Elem.action_button(Elem.ActionButtonProps.{ caption: "Choose folder", label: "Choose music folder", on_press: |current, _| scan(current) })]),
		Elem.panel(Elem.PanelProps.{ label: "Playback status", border_color: Gui.rgb(0x4f76c7) }, [Elem.text(state.status)]),
		library_view,
		Elem.row(Elem.RowProps.{ label: "Playback controls" }, [
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Previous", label: "Previous track", on_press: |current, _| step!(current, -1) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Play / Pause", label: "Toggle playback", on_press: |current, _| toggle(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Next", label: "Next track", on_press: |current, _| step!(current, 1) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Stop", label: "Stop playback", on_press: |current, _| stop(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Seek +100 ms", label: "Seek forward", on_press: |current, _| seek_forward(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Refresh", label: "Refresh playback status", on_press: |current, _| refresh_status(current) }),
		]),
	])
}
