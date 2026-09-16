## Explicit authority for bounded local-media playback. Tracks are opaque host
## resources loaded from a granted directory; applications never pass paths.
import Host
import Resource
import Files

Audio := [].{

	## Opaque authority over this application's audio output.
	Output := Resource.AudioOutput.{

		## Load one direct ordinary child of a granted directory as a track.
		load! : Output, Files.Dir.Read, Str => Try(LoadedTrack, AudioErr)
		load! = |Output.(output), directory, name| Host.audio_load!(output, directory.resource(), name).map_ok(|raw| { duration_ms: raw.duration_ms, track: Track.(raw.track) }).map_err(|raw| LoadAudioErr(decode_reason(raw.code)))
	}

	## One loaded, playable track held open by the host.
	Track := Resource.AudioTrack.{

		## Begin or resume playback.
		play! : Track => Try({}, AudioErr)
		play! = |Track.(track)| Host.audio_play!(track).map_err(|raw| PlayAudioErr(decode_reason(raw.code)))

		## Suspend playback, keeping the current position.
		pause! : Track => Try({}, AudioErr)
		pause! = |Track.(track)| Host.audio_pause!(track).map_err(|raw| PauseAudioErr(decode_reason(raw.code)))

		## Move the playback position.
		seek! : Track, U64 => Try({}, AudioErr)
		seek! = |Track.(track), position_ms| Host.audio_seek!(track, position_ms).map_err(|raw| SeekAudioErr(decode_reason(raw.code)))

		## Report this track's playback state, position, and duration.
		status! : Track => Try(Status, AudioErr)
		status! = |Track.(track)| Host.audio_status!(track).map_ok(|raw| { duration_ms: raw.duration_ms, position_ms: raw.position_ms, playback: decode_playback(raw.state) }).map_err(|raw| StatusAudioErr(decode_reason(raw.code)))

		## Stop playback and return the position to the start.
		stop! : Track => Try({}, AudioErr)
		stop! = |Track.(track)| Host.audio_stop!(track).map_err(|raw| StopAudioErr(decode_reason(raw.code)))
	}

	Playback : [Paused, Playing, Stopped]
	Status : { duration_ms : U64, position_ms : U64, playback : Playback }
	LoadedTrack : { duration_ms : U64, track : Track }
	Reason : [AccessDenied, DecodeFailed, InvalidCapability, InvalidName, OutputUnavailable, ResourceLimit, Unsupported, Unavailable]
	AudioErr : [AcquireAudioErr(Reason), LoadAudioErr(Reason), PauseAudioErr(Reason), PlayAudioErr(Reason), SeekAudioErr(Reason), StatusAudioErr(Reason), StopAudioErr(Reason)]

	## Acquire the audio-output authority granted by the host.
	acquire! : () => Try(Output, AudioErr)
	acquire! = || Host.audio_acquire!().map_ok(|output| Output.(output)).map_err(|raw| AcquireAudioErr(decode_reason(raw.code)))

	decode_playback = |code| match code {
		1 => Playing
		2 => Paused
		_ => Stopped
	}
	decode_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		2 => InvalidName
		3 => ResourceLimit
		4 => Unsupported
		5 => DecodeFailed
		6 => OutputUnavailable
		_ => Unavailable
	}
}
