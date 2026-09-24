## A table as Markdown, for pasting evidence into a review. Every row has the
## header's columns; a cell's pipes are escaped and its line breaks become
## spaces, so any text stays inside its cell.

Markdown := [].{

	## A titled pipe table.
	table : Str, List(Str), List(List(Str)) -> Str
	table = table

	## One cell's text, safe inside a pipe table.
	cell : Str -> Str
	cell = cell
}

cell : Str -> Str
cell = |text| text.replace_each("\\", "\\\\").replace_each("|", "\\|").replace_each("\n", " ")

line : List(Str) -> Str
line = |cells| "| ${Str.join_with(cells.map(cell), " | ")} |"

table : Str, List(Str), List(List(Str)) -> Str
table = |title, header, rows| {
	rule = "|${Str.join_with(header.map(|_| " --- "), "|")}|"
	body = rows.map(|row| line(row))
	"${Str.join_with(["### ${cell(title)}", "", line(header), rule].concat(body), "\n")}\n"
}

expect cell("a|b") == "a\\|b"
expect cell("two\nlines") == "two lines"
expect table("Triggers", ["trigger", "count"], [["click", "3"]]) == "### Triggers\n\n| trigger | count |\n| --- | --- |\n| click | 3 |\n"
expect table("Empty", ["a"], []) == "### Empty\n\n| a |\n| --- |\n"
