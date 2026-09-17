## Persistent traversal frames. Yielding across callbacks shares the tail;
## pushing and popping a frame never copies unrelated pending work.
WorkStack(a) :: [Empty, Node({ item : a, rest : WorkStack(a) })].{

	## A traversal with no pending frames.
	empty : WorkStack(a)
	empty = Empty

	## Add the next frame while sharing the existing tail.
	push : WorkStack(a), a -> WorkStack(a)
	push = |stack, item| Node({ item, rest: stack })

	## Return the next frame and remaining stack, or `Err(Empty)`.
	pop : WorkStack(a) -> Try({ item : a, rest : WorkStack(a) }, [Empty])
	pop = |stack| match stack {
		Empty => Err(Empty)
		Node(frame) => Ok(frame)
	}

	## Whether traversal has any pending frames.
	is_empty : WorkStack(a) -> Bool
	is_empty = |stack| match stack {
		Empty => True
		Node(_) => False
	}
}
