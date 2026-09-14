import Elem exposing [Elem]

Layout := [].{
	row : {}, List(Elem(a)) -> Elem(a)
	row = |_, children| Elem.row(children)

	col : {}, List(Elem(a)) -> Elem(a)
	col = |_, children| Elem.col(children)
}
