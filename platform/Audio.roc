## Explicit authority for bounded local-media playback. Tracks are opaque host
## resources loaded from a granted directory; applications never pass paths.
import Host
import Resource
import Files

Audio := [].{

	## The audio output the person granted: an opaque handle to the host's
	## output device. Tracks are loaded through it.
	Output := Resource.AudioOutput.{

		## Load one file of a granted directory as a track, by its name in that
		## directory. Call it from `Action.task`; decoding reads the file.
		load! : Output, Files.Dir.Read, Str => Try(LoadedTrack, AudioErr)
		load! = |Output.(handle), directory, name| Host.audio_load!(handle, directory.resource(), name).map_ok(|raw| { duration_ms: raw.duration_ms, track: Track.(raw.track) }).map_err(|raw| LoadAudioErr(decode_reason(raw.code)))
	}

	## A loaded track: an opaque handle to decoded audio the host holds.
	Track := Resource.AudioTrack.{

		## Start or resume playback.
		play! : Track => Try({}, AudioErr)
		play! = |Track.(handle)| Host.audio_play!(handle).map_err(|raw| PlayAudioErr(decode_reason(raw.code)))

		## Pause playback, keeping the position.
		pause! : Track => Try({}, AudioErr)
		pause! = |Track.(handle)| Host.audio_pause!(handle).map_err(|raw| PauseAudioErr(decode_reason(raw.code)))

		## Move the position, in milliseconds from the start.
		seek! : Track, U64 => Try({}, AudioErr)
		seek! = |Track.(handle), position_ms| Host.audio_seek!(handle, position_ms).map_err(|raw| SeekAudioErr(decode_reason(raw.code)))

		## The track's duration, position and playback state.
		status! : Track => Try(Status, AudioErr)
		status! = |Track.(handle)| Host.audio_status!(handle).map_ok(|raw| { duration_ms: raw.duration_ms, position_ms: raw.position_ms, playback: decode_playback(raw.state) }).map_err(|raw| StatusAudioErr(decode_reason(raw.code)))

		## Stop playback and return to the start.
		stop! : Track => Try({}, AudioErr)
		stop! = |Track.(handle)| Host.audio_stop!(handle).map_err(|raw| StopAudioErr(decode_reason(raw.code)))
	}

	Playback : [Paused, Playing, Stopped]
	Status : { duration_ms : U64, position_ms : U64, playback : Playback }
	LoadedTrack : { duration_ms : U64, track : Track }
	Reason : [AccessDenied, DecodeFailed, InvalidCapability, InvalidName, OutputUnavailable, ResourceLimit, Revoked, Unsupported, Unavailable]
	AudioErr : [AcquireAudioErr(Reason), LoadAudioErr(Reason), PauseAudioErr(Reason), PlayAudioErr(Reason), SeekAudioErr(Reason), StatusAudioErr(Reason), StopAudioErr(Reason)]

	acquire! : Resource.Access => Try(Output, AudioErr)
	acquire! = |_access| Host.audio_acquire!().map_ok(|handle| Output.(handle)).map_err(|raw| AcquireAudioErr(decode_reason(raw.code)))

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
		7 => Revoked
		_ => Unavailable
	}
}
