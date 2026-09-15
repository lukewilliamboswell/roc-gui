## Capability-scoped, read-only SQLite access. Connections can only be opened
## from one ordinary direct child of a granted directory.
import Files
import Host
import Resource

Sqlite := [].{
	Read : Resource.SqliteRead

	Value : [Bytes(List(U8)), Integer(I64), Null, Real(F64), String(Str)]
	Result : { columns : List(Str), rows : List(List(Value)) }
	Error : { code : [AccessDenied, Busy, Corrupt, InvalidCapability, InvalidName, InvalidQuery, Io, NotDatabase, ResourceLimit, Unsupported], message : Str }

	## Open a direct child database as an immutable, in-memory read-only
	## connection. The directory authority is consumed normally and may be
	## retained by application state through Roc reference counting.
	open_read! : Files.Dir.Read, Str => Try(Read, Error)
	open_read! = |directory, name| Host.sqlite_open_read!(directory, name).map_err(decode_error)

	## Execute one read-only statement and return typed cells. Query text, result
	## dimensions, and aggregate value bytes are bounded by the host.
	query! : Read, Str => Try(Result, Error)
	query! = |database, query| Host.sqlite_query!(database, query).map_ok(
		|raw| {
			columns: raw.columns,
			rows: raw.rows.map(|row| row.map(decode_value)),
		},
	).map_err(decode_error)

	decode_value = |raw| match raw.kind {
		0 => Null
		1 => Integer(raw.integer)
		2 => Real(raw.real)
		3 => String(raw.text)
		4 => Bytes(raw.bytes)
		_ => crash "invalid native SQLite value kind"
	}

	decode_error = |raw| {
		code = match raw.code {
			0 => AccessDenied
			1 => Busy
			2 => Corrupt
			3 => InvalidCapability
			4 => InvalidName
			5 => InvalidQuery
			6 => Io
			7 => NotDatabase
			8 => ResourceLimit
			9 => Unsupported
			_ => Unsupported
		}
		{ code, message: raw.message }
	}
}
