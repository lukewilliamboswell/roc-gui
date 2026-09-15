## App-scoped durable preferences. The host grants one private storage root;
## applications address bounded keys inside it and never receive a path.
import Host
import Resource

Preferences := [].{
	Store : Resource.Preferences
	Read : [Missing, Value(Str)]
	Error : { code : [AccessDenied, InvalidCapability, InvalidKey, Io, ResourceLimit, Unavailable], message : Str }

	open! : {} => Try(Store, Error)
	open! = |{}| Host.preferences_open!({}).map_err(decode_error)

	read! : Store, Str => Try(Read, Error)
	read! = |store, key| Host.preferences_read!(store, key).map_ok(|raw| if raw.found Value(raw.value) else Missing).map_err(decode_error)

	write_atomic! : Store, Str, Str => Try({}, Error)
	write_atomic! = |store, key, value| Host.preferences_write!(store, key, value).map_err(decode_error)

	decode_error = |raw| {
		code = match raw.code {
			0 => AccessDenied
			1 => InvalidCapability
			2 => InvalidKey
			3 => Io
			4 => ResourceLimit
			_ => Unavailable
		}
		{ code, message: raw.message }
	}
}
