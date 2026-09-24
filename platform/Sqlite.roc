## Capability-scoped, read-only SQLite access. Connections can only be opened
## from one ordinary direct child of a granted directory, or from one granted
## file.
import Files
import Host
import Resource

Sqlite := [].{

	## An open read-only connection to one database file.
	Db := Resource.SqliteRead.{

		## Execute one read-only statement and return typed cells. Query text,
		## result dimensions, and aggregate value bytes are bounded by the host;
		## a result longer than the row limit is a `ResourceLimit`.
		query! : Db, Str => Try(Result, SqliteErr)
		query! = |db, sql| db.query_with!(sql, [])

		## Execute one read-only statement with its `?` placeholders bound, in
		## order, to `params`. Values are bound, never spliced into the text, and
		## the count must match the statement's placeholders.
		query_with! : Db, Str, List(Value) => Try(Result, SqliteErr)
		query_with! = |Db.(database), sql, params| run!(database, sql, params, 0).map_ok(|page| { columns: page.columns, rows: page.rows })

		## Execute one read-only statement with bound parameters and return at
		## most `rows` rows, from 1 to the row limit. `more` reports whether the
		## result continues past the page; the next page is asked for with a
		## keyset or `LIMIT`/`OFFSET` bound as parameters.
		page! : Db, { sql : Str, params : List(Value), rows : U64 } => Try(Page, SqliteErr)
		page! = |Db.(database), request| if request.rows == 0 {
			Err(QueryDatabaseErr(ResourceLimit("a page holds at least one row")))
		} else {
			run!(database, request.sql, request.params, request.rows)
		}

		## Watch the database this connection reads: its file and its
		## write-ahead log. A committed write by any writer is a `Modified`
		## change, and a file renamed over the database's name, or the name
		## removed, is `Replaced`; the connection still reads the file it
		## opened, so a replaced database is read by opening it again. The
		## watch is derived from this connection, so withdrawing the grant the
		## database was opened through ends it.
		watch! : Db => Try(Files.Watch, SqliteErr)
		watch! = |Db.(database)| Host.sqlite_watch!(database).map_ok(Files.Watch.from_resource).map_err(|raw| WatchDatabaseErr(decode_reason(raw)))
	}

	Value : [Bytes(List(U8)), Integer(I64), Null, Real(F64), String(Str)]
	Result : { columns : List(Str), rows : List(List(Value)) }
	Page : { columns : List(Str), rows : List(List(Value)), more : Bool }

	## Portable failure categories with the native SQLite diagnostic retained.
	Reason : [AccessDenied(Str), Busy(Str), Corrupt(Str), Interrupted(Str), InvalidCapability(Str), InvalidName(Str), InvalidQuery(Str), Io(Str), NotDatabase(Str), ResourceLimit(Str), Revoked(Str), Unsupported(Str)]
	SqliteErr : [OpenDatabaseErr(Reason), QueryDatabaseErr(Reason), WatchDatabaseErr(Reason)]

	## Open a direct child database in place as a read-only connection. The
	## connection reads the file where it lies, including a write-ahead log a
	## writer is still appending to. The directory authority is consumed
	## normally and may be retained by application state through Roc reference
	## counting.
	open_read! : Files.Dir.Read, Str => Try(Db, SqliteErr)
	open_read! = |directory, name| Host.sqlite_open_read!(directory.resource(), name).map_ok(|database| Db.(database)).map_err(|raw| OpenDatabaseErr(decode_reason(raw)))

	## Open a granted file in place as a read-only connection, exactly as
	## `open_read!` opens a directory's child. The connection is derived from
	## the file grant, so withdrawing the file withdraws the connection.
	open_file_read! : Files.File.Read => Try(Db, SqliteErr)
	open_file_read! = |file| Host.sqlite_open_file_read!(file.resource()).map_ok(|database| Db.(database)).map_err(|raw| OpenDatabaseErr(decode_reason(raw)))

	run! : Resource.SqliteRead, Str, List(Value), U64 => Try(Page, SqliteErr)
	run! = |database, sql, params, page_rows| Host.sqlite_query!(database, { sql, params: params.map(encode_value), page_rows }).map_ok(
		|raw| {
			columns: raw.columns,
			rows: raw.rows.map(|row| row.map(decode_value)),
			more: raw.more,
		},
	).map_err(|raw| QueryDatabaseErr(decode_reason(raw)))

	encode_value : Value -> { bytes : List(U8), integer : I64, kind : U8, real : F64, text : Str }
	encode_value = |value| match value {
		Null => { bytes: [], integer: 0, kind: 0, real: 0, text: "" }
		Integer(number) => { bytes: [], integer: number, kind: 1, real: 0, text: "" }
		Real(number) => { bytes: [], integer: 0, kind: 2, real: number, text: "" }
		String(text) => { bytes: [], integer: 0, kind: 3, real: 0, text }
		Bytes(bytes) => { bytes, integer: 0, kind: 4, real: 0, text: "" }
	}

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
		11 => Interrupted(raw.message)
		_ => Unsupported(raw.message)
	}

	## Human-readable native detail without discarding the operation tag.
	detail : SqliteErr -> Str
	detail = |error| match error {
		OpenDatabaseErr(reason) => reason_detail(reason)
		QueryDatabaseErr(reason) => reason_detail(reason)
		WatchDatabaseErr(reason) => reason_detail(reason)
	}

	reason_detail = |reason| match reason {
		AccessDenied(message) => message
		Busy(message) => message
		Corrupt(message) => message
		InvalidCapability(message) => message
		InvalidName(message) => message
		InvalidQuery(message) => message
		Interrupted(message) => message
		Io(message) => message
		NotDatabase(message) => message
		ResourceLimit(message) => message
		Revoked(message) => message
		Unsupported(message) => message
	}
}
