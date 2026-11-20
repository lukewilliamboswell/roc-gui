## A table as Markdown, for pasting evidence into a review. Every row has the
## header's columns; a cell's pipes are escaped and its line breaks become
## spaces, so any text stays inside its cell.

Markdown := [].{

	## A titled pipe table.
	table : Str, List(Str), List(List(Str)) -> Str
	table = table_impl

	## One cell's text, safe inside a pipe table.
	cell : Str -> Str
	cell = cell_impl
}

cell_impl : Str -> Str
cell_impl = |text| text.replace_each("\\", "\\\\").replace_each("|", "\\|").replace_each("\n", " ")

line : List(Str) -> Str
line = |cells| "| ${Str.join_with(cells.map(cell_impl), " | ")} |"

table_impl : Str, List(Str), List(List(Str)) -> Str
table_impl = |title, header, rows| {
	rule = "|${Str.join_with(header.map(|_| " --- "), "|")}|"
	body = rows.map(|row| line(row))
	"${Str.join_with(["### ${cell_impl(title)}", "", line(header), rule].concat(body), "\n")}\n"
}

expect cell_impl("a|b") == "a\\|b"
expect cell_impl("two\nlines") == "two lines"
expect table_impl("Triggers", ["trigger", "count"], [["click", "3"]]) == "### Triggers\n\n| trigger | count |\n| --- | --- |\n| click | 3 |\n"
expect table_impl("Empty", ["a"], []) == "### Empty\n\n| a |\n| --- |\n"
