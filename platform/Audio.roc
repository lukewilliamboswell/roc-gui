## Explicit authority for bounded local-media playback. Tracks are opaque host
## resources loaded from a granted directory; applications never pass paths.
import Host
import Resource
import Files

Audio := [].{
	Output : Resource.AudioOutput
	Track : Resource.AudioTrack
	Playback : [Paused, Playing, Stopped]
	Status : { duration_ms : U64, position_ms : U64, playback : Playback }
	LoadedTrack : { duration_ms : U64, track : Track }
	Reason : [AccessDenied, DecodeFailed, InvalidCapability, InvalidName, OutputUnavailable, ResourceLimit, Unsupported, Unavailable]
	AudioErr : [AcquireAudioErr(Reason), LoadAudioErr(Reason), PauseAudioErr(Reason), PlayAudioErr(Reason), SeekAudioErr(Reason), StatusAudioErr(Reason), StopAudioErr(Reason)]

	acquire! : {} => Try(Output, AudioErr)
	acquire! = |{}| Host.audio_acquire!({}).map_err(|raw| AcquireAudioErr(decode_reason(raw.code)))

	load! : Output, Files.Dir.Read, Str => Try(LoadedTrack, AudioErr)
	load! = |output, directory, name| Host.audio_load!(output, directory, name).map_err(|raw| LoadAudioErr(decode_reason(raw.code)))

	play! : Track => Try({}, AudioErr)
	play! = |track| Host.audio_play!(track).map_err(|raw| PlayAudioErr(decode_reason(raw.code)))
	pause! : Track => Try({}, AudioErr)
	pause! = |track| Host.audio_pause!(track).map_err(|raw| PauseAudioErr(decode_reason(raw.code)))
	seek! : Track, U64 => Try({}, AudioErr)
	seek! = |track, position_ms| Host.audio_seek!(track, position_ms).map_err(|raw| SeekAudioErr(decode_reason(raw.code)))
	status! : Track => Try(Status, AudioErr)
	status! = |track| Host.audio_status!(track).map_ok(|raw| { duration_ms: raw.duration_ms, position_ms: raw.position_ms, playback: decode_playback(raw.state) }).map_err(|raw| StatusAudioErr(decode_reason(raw.code)))
	stop! : Track => Try({}, AudioErr)
	stop! = |track| Host.audio_stop!(track).map_err(|raw| StopAudioErr(decode_reason(raw.code)))

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
