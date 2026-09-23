import pf.Gui

## Presentation helpers for typed SQLite query results.
Query := [].{
	value_text : Gui.SqliteValue -> Str
	value_text = |value| match value {
		Null => "NULL"
		Integer(number) => number.to_str()
		Real(number) => number.to_str()
		String(text) => text
		Bytes(bytes) => "<${bytes.len().to_str()} bytes>"
	}

	## The SQLite storage class a value was read with.
	value_type : Gui.SqliteValue -> Str
	value_type = |value| match value {
		Null => "NULL"
		Integer(_) => "INTEGER"
		Real(_) => "REAL"
		String(_) => "TEXT"
		Bytes(_) => "BLOB"
	}

	row_text : List(Gui.SqliteValue) -> Str
	row_text = |row| Str.join_with(row.map(value_text), " | ")
}
