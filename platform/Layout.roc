import Elem exposing [Elem]

## Compatibility layout constructors. New code can use `Elem.row` and
## `Elem.col` directly.
Layout := [].{

	## Lay out children horizontally using native row properties.
	row : Elem.RowProps, List(Elem(a)) -> Elem(a)
	row = |props, children| Elem.row(props, children)

	## Lay out children vertically using native column properties.
	col : Elem.ColProps, List(Elem(a)) -> Elem(a)
	col = |props, children| Elem.col(props, children)
}
