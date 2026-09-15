import Elem exposing [Elem]

## Compatibility layout constructors. New code can use `Elem.row` and
## `Elem.col` directly.
Layout := [].{

	## Lay out children horizontally. The props record is reserved for future
	## layout options.
	row : {}, List(Elem(a)) -> Elem(a)
	row = |_, children| Elem.row(children)

	## Lay out children vertically. The props record is reserved for future
	## layout options.
	col : {}, List(Elem(a)) -> Elem(a)
	col = |_, children| Elem.col(children)
}
