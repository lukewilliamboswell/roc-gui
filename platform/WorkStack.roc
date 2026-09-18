## Persistent traversal frames. Owners box large payloads before insertion.
## Keep the recursive node boxed too: with the pinned development backend the
## inline and chunked representations inflate or copy generated continuation
## state and are measurably slower on repeated-selection scaling cases. Inline
## frames have also overflowed deep traversal on Windows, so this indirection is
## a cross-target correctness boundary rather than an optional allocation tweak.
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

expect {
	stack = WorkStack.empty.push(1).push(2).push(3)
	three = stack.pop() ?? crash "missing third frame"
	two = three.rest.pop() ?? crash "missing second frame"
	one = two.rest.pop() ?? crash "missing first frame"
	three.item == 3 and two.item == 2 and one.item == 1 and one.rest.is_empty()
}

expect {
	var $stack = WorkStack.empty
	var $pushed = 0
	while $pushed < 10000 {
		$stack = $stack.push($pushed)
		$pushed = $pushed + 1
	}
	var $expected = 10000
	var $valid = True
	while !$stack.is_empty() {
		frame = $stack.pop() ?? crash "missing scaling frame"
		$expected = $expected - 1
		$valid = $valid and frame.item == $expected
		$stack = frame.rest
	}
	$valid and $expected == 0
}
