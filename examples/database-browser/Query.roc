import pf.Gui

## Presentation helpers for typed SQLite query results.
Query := [].{
	value_text : Gui.Sqlite.Value -> Str
	value_text = |value| match value {
		Null => "NULL"
		Integer(number) => number.to_str()
		Real(number) => number.to_str()
		String(text) => text
		Bytes(bytes) => "<${bytes.len().to_str()} bytes>"
	}

	row_text : List(Gui.Sqlite.Value) -> Str
	row_text = |row| Str.join_with(row.map(value_text), " | ")
}
