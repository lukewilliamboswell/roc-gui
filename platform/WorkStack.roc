## Persistent traversal frames. Yielding across callbacks shares the tail;
## pushing and popping a frame never copies unrelated pending work.
## Keep frames boxed so each pending item has an explicit pointer-sized
## recursive tail. Inline frames have crashed deep traversal on Windows;
## the hover-grid suites exercise that cross-target scaling path.
WorkStack(a) :: [Empty, Node(Box({ item : a, rest : WorkStack(a) }))].{

	## A traversal with no pending frames.
	empty : WorkStack(a)
	empty = Empty

	## Add the next frame while sharing the existing tail.
	push : WorkStack(a), a -> WorkStack(a)
	push = |stack, item| Node(Box.box({ item, rest: stack }))

	## Return the next frame and remaining stack, or `Err(Empty)`.
	pop : WorkStack(a) -> Try({ item : a, rest : WorkStack(a) }, [Empty])
	pop = |stack| match stack {
		Empty => Err(Empty)
		Node(frame) => Ok(Box.unbox(frame))
	}

	## Whether traversal has any pending frames.
	is_empty : WorkStack(a) -> Bool
	is_empty = |stack| match stack {
		Empty => True
		Node(_) => False
	}
}
