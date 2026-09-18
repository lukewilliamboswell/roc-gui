## A private, fixed-result trampoline. Typed values live in continuation captures;
## neither the executor nor the host interprets application state.
## Keep scheduled continuations boxed. Their captures include typed application
## and lowering state; storing them inline recursively makes generated executor
## frames scale with the largest continuation environment.
Work :: [Done, Next(Box((() => Work))), Get(Box((() => Work))), Set(Box((() => Work))), Flush(Box((() => Work)))].{

	## Finish this chain of platform work.
	done : Work
	done = Done

	## Schedule the next continuation without growing the call stack.
	next : (() => Work) -> Work
	next = |resume| Next(Box.box(resume))

	## Schedule one configured getter and count it at execution.
	get : (() => Work) -> Work
	get = |resume| Get(Box.box(resume))

	## Schedule one configured setter and count it at execution.
	set : (() => Work) -> Work
	set = |resume| Set(Box.box(resume))

	## Report accumulated adapter counts before continuing into another work phase.
	flush : (() => Work) -> Work
	flush = |resume| Flush(Box.box(resume))

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
					$work = (Box.unbox(resume!))()
				}
				Get(resume!) => {
					$gets = $gets + 1
					$work = Done
					$work = (Box.unbox(resume!))()
				}
				Set(resume!) => {
					$sets = $sets + 1
					$work = Done
					$work = (Box.unbox(resume!))()
				}
				Flush(resume!) => {
					if $gets > 0 or $sets > 0 {
						record!($gets, $sets)
					}
					$gets = 0
					$sets = 0
					$work = Done
					$work = (Box.unbox(resume!))()
				}
			}
		}
	}
}
