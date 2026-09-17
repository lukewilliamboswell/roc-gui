## A private, fixed-result trampoline. Typed values live in continuation captures;
## neither the executor nor the host interprets application state.
Work :: [Done, Next(Box(() => Work)), Get(Box(() => Work)), Set(Box(() => Work)), Flush(Box(() => Work))].{
	done : Work
	done = Done

	next : (() => Work) -> Work
	next = |resume| Next(Box.box(resume))

	get : (() => Work) -> Work
	get = |resume| Get(Box.box(resume))

	set : (() => Work) -> Work
	set = |resume| Set(Box.box(resume))

	flush : (() => Work) -> Work
	flush = |resume| Flush(Box.box(resume))

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
				Next(box) => {
					resume! = Box.unbox(box)
					$work = Done
					$work = resume!()
				}
				Get(box) => {
					$gets = $gets + 1
					resume! = Box.unbox(box)
					$work = Done
					$work = resume!()
				}
				Set(box) => {
					$sets = $sets + 1
					resume! = Box.unbox(box)
					$work = Done
					$work = resume!()
				}
				Flush(box) => {
					if $gets > 0 or $sets > 0 {
						record!($gets, $sets)
					}
					$gets = 0
					$sets = 0
					resume! = Box.unbox(box)
					$work = Done
					$work = resume!()
				}
			}
		}
	}
}
