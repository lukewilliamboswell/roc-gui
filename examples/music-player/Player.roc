import pf.Gui

Player := [].{
	State : State

	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Gui.Access -> State
	init = |access| { access, alarm: False, art: NoArt, chosen: Nothing, generation: 0, library: Empty, playback: Idle, status: "Choose a music folder" }
	render : State -> Gui.Elem(State)
	render = render
}

## A queue row. `name` is the file the decoder is asked for; `title` is what a
## person reads. They differ because a file extension is a fact about storage,
## not about music, and a queue that shows one reads like a directory listing.
Track : { name : Str, title : Str }

Library : [Empty, Loaded({ directory : Gui.Files.Dir.Read, output : Gui.Audio.Output, tracks : List(Track) })]

Playback : [Idle, Active({ index : U64, paused : Bool, track : Gui.Audio.Track }), Stopped]

## The cover the sleeve shows. A photograph is too large to pay for in
## executable size, so it is not a compile-time file import: it lives in the
## asset set shipped beside the program and is read through a store.
Art : [NoArt, Cover(List(U8)), NoCover]

## The row a person last asked for. It is not the sounding row: a track is
## chosen the moment it is clicked and only starts once it has loaded, and a
## track that fails to decode stays chosen so the failure has a place to sit.
Chosen : [Nothing, At(U64)]

## `alarm` is the kind of the message in `status`, not a second message: a
## report or a failure. Carrying the kind beside the text is what lets a failure
## look like one. A decode error rendered in the same quiet grey as "Paused" is
## a designed state only by accident.
State : { access : Gui.Access, alarm : Bool, art : Art, chosen : Chosen, generation : U64, library : Library, playback : Playback, status : Str }

## The two ways of saying something. Every transition goes through one of them,
## so no path can leave a stale alarm colouring the next ordinary message.
report = |state, message| { ..state, alarm: False, status: message }

alarmed = |state, message| { ..state, alarm: True, status: message }

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
## The sleeve art travels with the application, so it is read from the
## application's own directory rather than from a root someone has to provision.
## `content_directory` is the provisioned root, and reaching for it here would
## mean a person who simply runs this example is told the cover is unavailable,
## which is a flag they did not pass rather than anything about the artwork.
##
## Every failure is one answer, `NoCover`, because there is nothing a person can
## do differently about a manifest that disagrees and about a directory that is
## not where the application was started from. The reason is not lost: the asset
## owner's counters separate a refused open from a refused read.
read_cover! : Gui.Access => Art
read_cover! = |access| match access.assets!(Gui.Assets.with_manifest(Gui.Assets.working_directory("examples/music-player/assets"), art_manifest)) {
	Err(_) => NoCover
	Ok(store) => match store.read!("art/nocturne-cover.jpg") {
		Err(_) => NoCover
		Ok(bytes) => Cover(bytes)
	}
}

is_audio = |name| Str.ends_with(name, ".wav")

## The title a row shows: the file name without the extension the host needs.
## A name that is nothing but an extension keeps its name, so a row can never
## come out blank and unclickable.
track_title = |name| {
	bytes = Str.to_utf8(name)
	length = List.len(bytes)
	if length > 4 {
		match Str.from_utf8(bytes.take_first(length - 4)) {
			Ok(title) => title
			Err(_) => name
		}
	} else {
		name
	}
}

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

scan = |state| Gui.Action.task({
	pending: report(state, "Scanning…"),
	run: || {

		## The cover is read whatever the chooser goes on to answer. A folder a
		## person declined to pick is not a reason for the sleeve to stay bare.
		art = read_cover!(state.access)
		outcome = match state.access.pick_directory!() {
			Err(PickDirectoryErr(Unavailable)) => ScanFailed("This system offers no folder chooser")
			Err(_) => ScanFailed("Music folder access was denied")
			Ok(Canceled) => ScanCanceled
			Ok(Chosen(selection)) => match state.access.audio!() {
				Err(err) => ScanFailed(audio_error(err))
				Ok(output) => match selection.directory.list!() {
					Err(_) => ScanFailed("Music folder could not be read")
					Ok(entries) => {
						tracks = List.keep_oks(
							entries,
							|entry| if entry.kind == File and is_audio(entry.name) {
								Ok({ name: entry.name, title: track_title(entry.name) })
							} else {
								Err({})
							},
						)
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
			ScanFailed(message) => Gui.Action.update(alarmed(dressed, message))
			ScanCanceled => Gui.Action.update(report(dressed, "Folder choice canceled"))
			Scanned(library) => Gui.Action.update(report({ ..dressed, chosen: Nothing, library: Loaded(library), playback: Idle }, "${U64.to_str(List.len(library.tracks))} tracks"))
		}
	},
})

play_index = |state, library, index| match library.tracks.get(index) {
	Err(_) => Gui.Action.update(state)
	Ok(item) => {
		generation = state.generation + 1
		Gui.Action.task({
			pending: report({ ..state, chosen: At(index), generation }, "Loading…"),
			run: || match Gui.Audio.load!(library.output, library.directory, item.name) {
				Err(err) => PlayFailed(generation, audio_error(err))
				Ok(loaded) => match Gui.Audio.play!(loaded.track) {
					Err(err) => PlayFailed(generation, audio_error(err))
					Ok(_) => PlayStarted(generation, index, loaded.track)
				}
			},
			resolve: |latest, result| match result {
				PlayFailed(request, message) => if request == latest.generation {
					Gui.Action.update(alarmed(latest, message))
				} else {
					Gui.Action.update(latest)
				}
				PlayStarted(request, started_index, track) => if request == latest.generation {
					Gui.Action.update(report({ ..latest, playback: Active({ index: started_index, paused: False, track }) }, "Playing"))
				} else {
					Gui.Action.task({ pending: latest, run: || Gui.Audio.stop!(track), resolve: |current, _| Gui.Action.update(current) })
				}
			},
		})
	}
}

stop = |state| match state.playback {
	Active(current) => Gui.Action.task({
		pending: report({ ..state, generation: state.generation + 1 }, "Stopping…"),
		run: || Gui.Audio.stop!(current.track),
		resolve: |latest, result| match result {
			Ok(_) => Gui.Action.update(report({ ..latest, chosen: Nothing, playback: Stopped }, "Stopped"))
			Err(_) => Gui.Action.update(alarmed(latest, "Stop failed"))
		},
	})
	_ => Gui.Action.update(state)
}

## How far a skip moves. Five seconds is a musical distance rather than a
## machine one: it is long enough to hear that the track moved.
skip_ahead_ms = 5000

## Skipping forward is a genuinely relative move: the position is read, and the
## seek goes to where the track actually is plus the skip. A control captioned
## with an offset that quietly seeks to a fixed millisecond is a lie the first
## press hides and the second press exposes.
skip_forward = |state| match state.playback {
	Active(current) => Gui.Action.task({
		pending: report(state, "Skipping…"),
		run: || match Gui.Audio.status!(current.track) {
			Err(err) => SkipFailed(audio_error(err))
			Ok(status) => {
				target = status.position_ms + skip_ahead_ms
				match Gui.Audio.seek!(current.track, target) {
					Err(err) => SkipFailed(audio_error(err))
					Ok(_) => Skipped(target)
				}
			}
		},
		resolve: |latest, result| match result {
			SkipFailed(message) => Gui.Action.update(alarmed(latest, message))
			Skipped(position) => Gui.Action.update(report(latest, "Position ${U64.to_str(position)} ms"))
		},
	})
	_ => Gui.Action.update(state)
}

show_position = |state| match state.playback {
	Active(current) => Gui.Action.task({
		pending: state,
		run: || Gui.Audio.status!(current.track),
		resolve: |latest, result| match result {
			Ok(status) => Gui.Action.update(report(latest, "Position ${U64.to_str(status.position_ms)} ms"))
			Err(err) => Gui.Action.update(alarmed(latest, audio_error(err)))
		},
	})
	_ => Gui.Action.update(state)
}

## The title of a row, for the messages that name it. A transport whose Resume
## says only "Playing" sends a person back to the queue to find out what they
## just resumed.
row_title = |state, index| match state.library {
	Loaded(library) => match library.tracks.get(index) {
		Ok(track) => track.title
		Err(_) => "this track"
	}
	Empty => "this track"
}

toggle = |state| match state.playback {
	Idle | Stopped => match state.library {
		Empty => Gui.Action.update(state)
		Loaded(library) => play_index(state, library, 0)
	}
	Active(current) => if current.paused {
		Gui.Action.task({
			pending: report(state, "Resuming…"),
			run: || Gui.Audio.play!(current.track),
			resolve: |latest, result| match result {
				Ok(_) => Gui.Action.update(report({ ..latest, playback: Active({ ..current, paused: False }) }, "Playing"))
				Err(_) => Gui.Action.update(alarmed(latest, "Resume failed"))
			},
		})
	} else {
		Gui.Action.task({
			pending: report(state, "Pausing…"),
			run: || Gui.Audio.pause!(current.track),
			resolve: |latest, result| match result {
				Ok(_) => Gui.Action.update(report({ ..latest, playback: Active({ ..current, paused: True }) }, "Paused"))
				Err(_) => Gui.Action.update(alarmed(latest, "Pause failed"))
			},
		})
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
	Nothing => if delta < 0 {
		len - 1
	} else {
		0
	}
	At(index) => if delta < 0 {
		if index == 0 {
			0
		} else {
			index - 1
		}
	} else if index + 1 >= len {
		index
	} else {
		index + 1
	}
}

step = |state, delta| match state.library {
	Empty => Gui.Action.update(state)
	Loaded(library) => {
		len = List.len(library.tracks)
		if len == 0 {
			Gui.Action.update(state)
		} else {
			next = step_target(step_origin(state), len, delta)
			match state.playback {
				Active(current) => stop_then_play(state, current.track, next)
				_ => play_index(state, library, next)
			}
		}
	}
}

stop_then_play = |state, track, next| Gui.Action.task({
	pending: report({ ..state, generation: state.generation + 1 }, "Changing track…"),
	run: || Gui.Audio.stop!(track),
	resolve: |latest, result| match result {
		Err(err) => Gui.Action.update(alarmed(latest, audio_error(err)))

		## The old track really has stopped, so the transport stops believing it
		## is sounding. Otherwise a load that then fails leaves a phantom Active
		## row, and the next step walks away from that instead of from the row
		## the person is standing on.
		Ok(_) => match latest.library {
			Empty => Gui.Action.update({ ..latest, playback: Stopped })
			Loaded(latest_library) => play_index({ ..latest, playback: Stopped }, latest_library, next)
		}
	},
})

## High-contrast night. A near-black ground, one vivid ember accent reserved
## for the primary transport and the track that is sounding, and pill controls
## whose hover and press colours are always a visible step apart.
ground = 0x08080b.Gui.Color

surface = 0x0b0b10.Gui.Color

row_rest = 0x15151d.Gui.Color

row_hover = 0x23232f.Gui.Color

row_press = 0x32323f.Gui.Color

hairline = 0x20202b.Gui.Color

ink = 0xf2efec.Gui.Color

muted = 0x8b8798.Gui.Color

accent = 0xff4b12.Gui.Color

accent_hot = 0xff7040.Gui.Color

accent_deep = 0xc2360b.Gui.Color

accent_tint = 0x2b1109.Gui.Color

accent_tint_hot = 0x3a1710.Gui.Color

accent_tint_press = 0x4a1d13.Gui.Color

## Failure is not the accent in a darker shade: the ember means "this is the
## music", so a message that borrowed it would say the opposite of what it
## means. A cooler red sits far enough from the orange to be told apart at a
## glance on a near-black ground.
alarm = 0xff8ba0.Gui.Color

alarm_deep = 0x8d2d40.Gui.Color

alarm_tint = 0x2a1118.Gui.Color

on_accent = 0x0a0a0c.Gui.Color

## A chosen row that is not yet the sounding one is Waiting, which is what makes
## a click visible while the next track loads or after one failed to decode.
active_index = |state| {
	live = match state.playback {
		Active(current) => { index: At(current.index), paused: current.paused }
		_ => { index: Nothing, paused: False }
	}
	mark = |index| if live.paused Held(index) else Sounding(index)

	## A chosen row that never started is either still loading or has failed,
	## and those are not the same state to stand in front of.
	chosen_mark = |index| if state.alarm Failed(index) else Waiting(index)
	match state.chosen {
		At(index) => if live.index == At(index) mark(index) else chosen_mark(index)
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

		## The row a person pressed whose track refused to load. It keeps its
		## place in the queue and wears the failure, so the message in the
		## status panel has something on screen to be about.
		Failed(active) if active == index => { bg: alarm_tint, hover_bg: alarm_tint, active_bg: alarm_tint, fg: alarm, border_color: alarm_deep, border_width: 1 }
		Waiting(active) if active == index => { bg: accent_tint, hover_bg: accent_tint_hot, active_bg: accent_tint_press, fg: muted, border_color: hairline, border_width: 1 }
		_ => { bg: row_rest, hover_bg: row_hover, active_bg: row_press, fg: ink, border_color: hairline, border_width: 0 }
	}
	Gui.button({
		caption: track.title,
		label: "Play ${track.title}",
		on_press: |current, _| play_index(current, library, index),
		width: Fill,
		height: Fill,

		## A queue reads down its left edge. Centred rows make a person's eye
		## hunt for the start of every title.
		justify: Start,
		align: Center,
		padding: 16,
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
		$items = $items.append({ key: index, content: track_row(library, index, track, marker) })
		$index = index + 1
	}
	$items
}

transport = |caption, name, press| Gui.button({
	caption,
	label: name,
	on_press: press,
	padding: 18,
	padding_top: Px(10),
	padding_bottom: Px(10),
	radius: 24,
	font_size: 15,
	bg: 0x15151d,
	hover_bg: 0x23232f,
	active_bg: 0x32323f,
	fg: ink,
	border_color: hairline,
	border_width: 1,
})

primary_transport = |caption| Gui.button({
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

empty_sleeve = Gui.row({ label: "Sleeve", width: Px(sleeve_size), height: Px(sleeve_size), min_width: Px(sleeve_size), min_height: Px(sleeve_size), padding: 0, gap: 0, bg: row_rest, border_color: hairline, border_width: 1, radius: 12 }, [])

sleeve = |art| match art {
	Cover(bytes) => Gui.image({ label: "Cover art", bytes, format: Jpeg, fit: Cover, width: Px(sleeve_size), height: Px(sleeve_size), min_width: Px(sleeve_size), min_height: Px(sleeve_size), radius: 12 })
	NoArt | NoCover => empty_sleeve
}

## A missing cover is said once, quietly, and only after the read was tried.
## An empty square with no explanation is a defect a person cannot report.
sleeve_caption = |art| match art {
	NoCover => [Gui.styled_text({ value: "Cover art unavailable", fg: muted, font_size: 13, font_weight: 400 })]
	NoArt | Cover(_) => []
}

toggle_caption = |state| match state.playback {
	Active(current) => if current.paused "Resume" else "Pause"
	_ => "Play"
}

## The line the sleeve is a sleeve for. It is derived from the row the transport
## is standing on rather than stored, so it cannot drift from the queue, and it
## survives every message that follows: pausing, skipping and reading the
## position all replace the status line underneath and leave the title alone.
## Without it, pressing Pause erases the only place the track was named.
now_playing_title = |state| match active_index(state) {
	Sounding(index) | Held(index) | Waiting(index) | Failed(index) => row_title(state, index)
	Silent => "Nothing playing"
}

render : State -> Gui.Elem(State)
render = |state| {
	library_view = match state.library {
		Empty => Gui.panel(
			{ label: "Music library", grow: True, width: Fill, padding: 28, bg: surface, border_color: hairline, radius: 16, fg: muted, font_size: 15 },
			[
				Gui.text("No folder chosen yet."),
				Gui.text("Grant a music folder to build the queue."),
			],
		)

		## The queue is its own surface. It carries the dark ground, the inset,
		## the corner, and the space between rows itself, so there is no padded
		## panel wrapped around it whose only job was to be the thing the list
		## is sitting on.
		Loaded(library) => Gui.virtual_list({
			label: "Tracks",
			row_height: 44,
			row_gap: 6,
			items: track_items(state, library),
			grow: True,
			width: Fill,
			padding: 10,
			bg: surface,
			border_color: hairline,
			border_width: 1,
			radius: 16,
		})
	}
	Gui.col(
		{ label: "Music player", width: Fill, height: Fill, grow: True, padding: 26, gap: 18, bg: ground, fg: ink, font_size: 15 },
		[
			Gui.row(
				{ label: "Header", width: Fill, gap: 16 },
				[
					Gui.styled_text({ value: "NOCTURNE", fg: accent, font_size: 28, font_weight: 700 }),
					Gui.button({
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
				],
			),
			Gui.panel(
				{ label: "Playback status", width: Fill, padding: 18, gap: 18, radius: 16, bg: surface, border_color: hairline, fg: muted, font_size: 13, font_weight: 600 },
				[
					Gui.row(
						{ label: "Now playing", width: Fill, gap: 18, padding: 0, align: Center },
						[
							sleeve(state.art),
							Gui.col(
								{ label: "Now playing text", grow: True, gap: 6, padding: 0 },
								[
									Gui.text("NOW PLAYING"),
									Gui.styled_text({ value: now_playing_title(state), fg: ink, font_size: 19, font_weight: 400 }),
									Gui.styled_text({ value: state.status, fg: if state.alarm alarm else muted, font_size: 13, font_weight: 400 }),
								].concat(sleeve_caption(state.art)),
							),
						],
					),
				],
			),
			library_view,
			Gui.row(
				{ label: "Playback controls", width: Fill, gap: 12 },
				[
					transport("Previous", "Previous track", |current, _| step(current, -1)),
					primary_transport(toggle_caption(state)),
					transport("Next", "Next track", |current, _| step(current, 1)),
					transport("Stop", "Stop playback", |current, _| stop(current)),
					transport("Skip 5 s", "Skip forward five seconds", |current, _| skip_forward(current)),
					transport("Position", "Show playback position", |current, _| show_position(current)),
				],
			),
		],
	)
}
