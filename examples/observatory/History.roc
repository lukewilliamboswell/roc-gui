## Back and forward over the places a person jumped between. A jump pushes the
## place being left; going back returns to it and keeps the place left behind
## for going forward again. A new jump forgets the forward places, as a browser
## does.

## The places behind and ahead of the current one, nearest last.
Trail(place) : { back : List(place), forward : List(place) }

History := [].{
	Trail(place) : Trail(place)

	empty : Trail(place)
	empty = { back: [], forward: [] }

	## How many places back remembers; the oldest are forgotten first.
	depth : U64
	depth = depth

	## Leave `current` for somewhere new.
	push : Trail(place), place -> Trail(place)
	push = |history, current| { back: keep_recent(history.back.append(current)), forward: [] }

	## The place before `current`, and the history with `current` ahead.
	back : Trail(place), place -> [None, Some({ history : Trail(place), place : place })]
	back = |history, current| match history.back.last() {
		Ok(place) => Some({ history: { back: history.back.drop_last(1), forward: history.forward.append(current) }, place })
		Err(_) => None
	}

	## The place after `current`, and the history with `current` behind.
	forward : Trail(place), place -> [None, Some({ history : Trail(place), place : place })]
	forward = |history, current| match history.forward.last() {
		Ok(place) => Some({ history: { back: keep_recent(history.back.append(current)), forward: history.forward.drop_last(1) }, place })
		Err(_) => None
	}
}

depth : U64
depth = 100

keep_recent : List(place) -> List(place)
keep_recent = |places| if places.len() > depth places.drop_first(places.len() - depth) else places

expect {
	visited = History.push(History.push(History.empty, 1.I64), 2)
	match History.back(visited, 3) {
		Some(went) => went.place == 2 and went.history.forward == [3]
		None => False
	}
}

expect {
	went = History.push(History.push(History.empty, 1.I64), 2)
	match History.back(went, 3) {
		Some(back) => match History.forward(back.history, back.place) {
			Some(ahead) => ahead.place == 3 and ahead.history.back == [1, 2] and ahead.history.forward == []
			None => False
		}
		None => False
	}
}

# A new jump forgets what was ahead.
expect {
	went = History.push(History.empty, 1.I64)
	match History.back(went, 2) {
		Some(back) => History.push(back.history, back.place).forward == []
		None => False
	}
}

expect History.back(History.empty, 1.I64) == None
