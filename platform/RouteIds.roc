## Private append-only route ownership metadata. A shared append copies at
## most one fixed-size chunk, never the entire owner's accumulated route list.
RouteIds :: [Empty, Chunk(List(U64), Box(RouteIds))].{

	## No routes registered to this owner.
	empty : RouteIds
	empty = Empty

	## Record a route for retirement when its owner is removed.
	append : RouteIds, U64 -> RouteIds
	append = |ids, id| match ids {
		Empty => Chunk([id], Box.box(Empty))
		Chunk(head, tail) => if head.len() < 64 {
			Chunk(head.append(id), tail)
		} else {
			Chunk([id], Box.box(ids))
		}
	}

	## Removal only needs membership, not emission order. Visit newest chunks
	## first so traversal can tail-call without a separate reversal buffer.
	fold : RouteIds, a, (a, U64 -> a) -> a
	fold = |ids, initial, visit| match ids {
		Empty => initial
		Chunk(head, tail) => {
			var $result = initial
			for id in head {
				$result = visit($result, id)
			}
			fold(Box.unbox(tail), $result, visit)
		}
	}
}

expect RouteIds.fold(RouteIds.empty, 0.U64, |count, _| count + 1) == 0

expect {
	var $ids = RouteIds.empty
	var $next = 0.U64
	for _ in List.repeat({}, 4097) {
		$ids = RouteIds.append($ids, $next)
		$next = $next + 1
	}
	original = $ids
	extended = RouteIds.append(original, 4097)
	seen = RouteIds.fold(original, List.repeat(False, 4097), |flags, id| flags.set(id, True) ?? crash "unexpected route ID")
	RouteIds.fold(original, { count: 0.U64, sum: 0.U64 }, |acc, id| { count: acc.count + 1, sum: acc.sum + id }) == { count: 4097, sum: 8390656 }
		and RouteIds.fold(extended, 0.U64, |count, _| count + 1) == 4098
			and seen.all(|present| present)
}
