## A private, fixed-result trampoline. Typed values live in continuation captures;
## neither the executor nor the host interprets application state.
Work :: [Done, Next((() => Work)), Get((() => Work)), Set((() => Work)), Flush((() => Work))].{

	## Finish this chain of platform work.
	done : Work
	done = Done

	## Schedule the next continuation without growing the call stack.
	next : (() => Work) -> Work
	next = |resume| Next(resume)

	## Schedule one configured getter and count it at execution.
	get : (() => Work) -> Work
	get = |resume| Get(resume)

	## Schedule one configured setter and count it at execution.
	set : (() => Work) -> Work
	set = |resume| Set(resume)

	## Report accumulated adapter counts before continuing into another work phase.
	flush : (() => Work) -> Work
	flush = |resume| Flush(resume)

	## Execute continuations iteratively, reporting getter and setter counts.
	run! : Work, (U64, U64 => {}) => {}
	run! = |initial, record!| {
		var $work = initial
		var $gets = 0.U64
		var $sets = 0.U64
		var $running = True
		while $running {
			match $work {
				Done => {
					if $gets > 0 or $sets > 0 {
						record!($gets, $sets)
					}
					$running = False
				}
				Next(resume!) => {
					$work = Done
					$work = resume!()
				}
				Get(resume!) => {
					$gets = $gets + 1
					$work = Done
					$work = resume!()
				}
				Set(resume!) => {
					$sets = $sets + 1
					$work = Done
					$work = resume!()
				}
				Flush(resume!) => {
					if $gets > 0 or $sets > 0 {
						record!($gets, $sets)
					}
					$gets = 0
					$sets = 0
					$work = Done
					$work = resume!()
				}
			}
		}
	}
}
