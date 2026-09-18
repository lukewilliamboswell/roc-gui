## Capability-scoped, read-only SQLite access. Connections can only be opened
## from one ordinary direct child of a granted directory.
import Files
import Host
import Resource

Sqlite := [].{
	## An open read-only connection to one database file.
	Db := Resource.SqliteRead.{

		## Execute one read-only statement and return typed cells. Query text,
		## result dimensions, and aggregate value bytes are bounded by the host.
		query! : Db, Str => Try(Result, SqliteErr)
		query! = |Db.(database), query| Host.sqlite_query!(database, query).map_ok(
			|raw| {
				columns: raw.columns,
				rows: raw.rows.map(|row| row.map(decode_value)),
			},
		).map_err(|raw| QueryDatabaseErr(decode_reason(raw)))
	}

	Value : [Bytes(List(U8)), Integer(I64), Null, Real(F64), String(Str)]
	Result : { columns : List(Str), rows : List(List(Value)) }
	## Portable failure categories with the native SQLite diagnostic retained.
	Reason : [AccessDenied(Str), Busy(Str), Corrupt(Str), InvalidCapability(Str), InvalidName(Str), InvalidQuery(Str), Io(Str), NotDatabase(Str), ResourceLimit(Str), Revoked(Str), Unsupported(Str)]
	SqliteErr : [OpenDatabaseErr(Reason), QueryDatabaseErr(Reason)]

	## Open a direct child database as an immutable, in-memory read-only
	## connection. The directory authority is consumed normally and may be
	## retained by application state through Roc reference counting.
	open_read! : Files.Dir.Read, Str => Try(Db, SqliteErr)
	open_read! = |directory, name| Host.sqlite_open_read!(directory.resource(), name).map_ok(|database| Db.(database)).map_err(|raw| OpenDatabaseErr(decode_reason(raw)))

	decode_value = |raw| match raw.kind {
		0 => Null
		1 => Integer(raw.integer)
		2 => Real(raw.real)
		3 => String(raw.text)
		4 => Bytes(raw.bytes)
		_ => crash "invalid native SQLite value kind"
	}

	decode_reason = |raw| match raw.code {
		0 => AccessDenied(raw.message)
		1 => Busy(raw.message)
		2 => Corrupt(raw.message)
		3 => InvalidCapability(raw.message)
		4 => InvalidName(raw.message)
		5 => InvalidQuery(raw.message)
		6 => Io(raw.message)
		7 => NotDatabase(raw.message)
		8 => ResourceLimit(raw.message)
		9 => Unsupported(raw.message)
		10 => Revoked(raw.message)
		_ => Unsupported(raw.message)
	}

	## Human-readable native detail without discarding the operation tag.
	detail : SqliteErr -> Str
	detail = |error| match error {
		OpenDatabaseErr(reason) => reason_detail(reason)
		QueryDatabaseErr(reason) => reason_detail(reason)
	}

	reason_detail = |reason| match reason {
		AccessDenied(message) => message
		Busy(message) => message
		Corrupt(message) => message
		InvalidCapability(message) => message
		InvalidName(message) => message
		InvalidQuery(message) => message
		Io(message) => message
		NotDatabase(message) => message
		ResourceLimit(message) => message
		Revoked(message) => message
		Unsupported(message) => message
	}
}
