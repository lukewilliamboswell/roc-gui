## The command palette's matching: what a typed query finds among the palette's
## candidates, and in what order. A query matches a candidate when its letters
## occur in order in the candidate's kind and title, ignoring ASCII case; runs
## of consecutive letters and letters that start a word rank higher. What the
## candidates are, and what choosing one does, belongs to the application.

## One thing the palette can find: what kind of thing it is, what it is
## called, a line about it, and what choosing it asks for.
Candidate(a) : { kind : Str, title : Str, detail : Str, act : a }

Palette := [].{
	Candidate(a) : Candidate(a)

	## The candidates a query finds, best first, at most `limit` of them. Equal
	## scores keep the order the candidates were given in, and an empty query
	## finds every candidate in that order.
	rank : Str, List(Candidate(a)), U64 -> List(Candidate(a))
	rank = rank

	## How well `query` matches `text`: `None` when its letters do not occur in
	## order, otherwise a score that grows with runs and word starts.
	score : Str, Str -> [None, Some(I64)]
	score = score

	## A query naming a cycle or a step by number, such as `cycle 12` or
	## `Step 3`.
	numbered : Str -> [None, Cycle(I64), Step(I64)]
	numbered = numbered
}

## ASCII upper case to lower case; every other byte is itself.
fold : U8 -> U8
fold = |byte| if byte >= 65 and byte <= 90 byte + 32 else byte

## Whether a byte separates words, so the byte after it starts one.
separates : U8 -> Bool
separates = |byte| byte == 32 or byte == 45 or byte == 95 or byte == 46 or byte == 47 or byte == 58 or byte == 35

score : Str, Str -> [None, Some(I64)]
score = |query, text| {
	wanted = query.to_utf8().keep_if(|byte| byte != 32).map(fold)
	haystack = text.to_utf8().map(fold)
	var $total = 0.I64
	var $next = 0.U64
	var $matched_last = False
	var $position = 0.U64
	for byte in haystack {
		matches = match wanted.get($next) {
			Ok(letter) => letter == byte
			Err(_) => False
		}
		if matches {
			starts_word = $position == 0 or separates(haystack.get($position - 1) ?? 32)
			$total = $total + 1 + (if $matched_last 5 else 0) + (if starts_word 3 else 0)
			$next = $next + 1
		}
		$matched_last = matches
		$position = $position + 1
	}
	if $next == wanted.len() Some($total) else None
}

rank : Str, List(Candidate(a)), U64 -> List(Candidate(a))
rank = |query, candidates, limit| {
	var $found = []
	var $index = 0.I64
	for candidate in candidates {
		match score(query, "${candidate.kind} ${candidate.title}") {
			Some(points) => {
				$found = $found.append({ points, index: $index, candidate })
			}
			None => {}
		}
		$index = $index + 1
	}
	ordered = List.sort_with(
		$found,
		|left, right| if left.points > right.points {
			Before
		} else if left.points < right.points {
			After
		} else if left.index < right.index {
			Before
		} else if left.index > right.index {
			After
		} else {
			Same
		},
	)
	ordered.take_first(limit).map(|found| found.candidate)
}

## The digits of a query after a word, as a number.
number_after : List(U8), List(U8) -> [None, Some(I64)]
number_after = |bytes, word| if bytes.starts_with(word) {
	digits = bytes.drop_first(word.len()).drop_if(|byte| byte == 32)
	if digits.is_empty() or digits.len() > 18 or !digits.all(|byte| byte >= 48 and byte <= 57) {
		None
	} else {
		Some(digits.fold(0.I64, |total, byte| total * 10 + (byte - 48).to_i64()))
	}
} else {
	None
}

numbered : Str -> [None, Cycle(I64), Step(I64)]
numbered = |query| {
	bytes = query.trim().to_utf8().map(fold)
	match number_after(bytes, "cycle".to_utf8()) {
		Some(number) => Cycle(number)
		None => match number_after(bytes, "step".to_utf8()) {
			Some(number) => Step(number)
			None => None
		}
	}
}

expect score("hov", "Trigger hover-enter") != None
expect score("xyz", "Trigger hover-enter") == None
expect score("HOV", "trigger hover-enter") == score("hov", "Trigger Hover-enter")
# A run at a word's start outranks the same letters scattered.
expect {
	points = |found| match found {
		Some(value) => value
		None => 0
	}
	points(score("int", "View Interactions")) > points(score("int", "Trigger input-text"))
}
expect numbered("cycle 12") == Cycle(12)
expect numbered("  Step 3 ") == Step(3)
expect numbered("cycle") == None
expect numbered("cycles 4") == None
expect {
	candidates = [
		{ kind: "Trigger", title: "input", detail: "", act: 1.I64 },
		{ kind: "View", title: "Interactions", detail: "", act: 2 },
		{ kind: "View", title: "Overview", detail: "", act: 3 },
	]
	rank("int", candidates, 5).map(|found| found.act) == [2, 1] and rank("", candidates, 2).map(|found| found.act) == [1, 2]
}
