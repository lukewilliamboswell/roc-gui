## App-scoped durable preferences. The host grants one private storage root;
## applications address bounded keys inside it and never receive a path.
import Host
import Resource

Preferences := [].{
	Store : Resource.Preferences
	Read : [Missing, Value(Str)]
	Reason : [AccessDenied, InvalidCapability, InvalidKey, Io, ResourceLimit, Unavailable]
	PreferencesErr : [OpenPreferencesErr(Reason), ReadPreferenceErr(Reason), WritePreferenceErr(Reason)]

	open! : {} => Try(Store, PreferencesErr)
	open! = |{}| Host.preferences_open!({}).map_err(|raw| OpenPreferencesErr(decode_reason(raw.code)))

	read! : Store, Str => Try(Read, PreferencesErr)
	read! = |store, key| Host.preferences_read!(store, key).map_ok(|raw| if raw.found Value(raw.value) else Missing).map_err(|raw| ReadPreferenceErr(decode_reason(raw.code)))

	write_atomic! : Store, Str, Str => Try({}, PreferencesErr)
	write_atomic! = |store, key, value| Host.preferences_write!(store, key, value).map_err(|raw| WritePreferenceErr(decode_reason(raw.code)))

	decode_reason = |code| {
		match code {
			0 => AccessDenied
			1 => InvalidCapability
			2 => InvalidKey
			3 => Io
			4 => ResourceLimit
			_ => Unavailable
		}
	}
}
