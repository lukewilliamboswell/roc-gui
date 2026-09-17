## Persistent traversal frames. Yielding across callbacks shares the tail;
## pushing and popping a frame never copies unrelated pending work.
WorkStack(a) :: [Empty, Node(Box({ item : a, rest : WorkStack(a) }))].{
	empty : WorkStack(a)
	empty = Empty

	push : WorkStack(a), a -> WorkStack(a)
	push = |stack, item| Node(Box.box({ item, rest: stack }))

	pop : WorkStack(a) -> Try({ item : a, rest : WorkStack(a) }, [Empty])
	pop = |stack| match stack {
		Empty => Err(Empty)
		Node(frame) => Ok(Box.unbox(frame))
	}

	is_empty : WorkStack(a) -> Bool
	is_empty = |stack| match stack {
		Empty => True
		Node(_) => False
	}
}
