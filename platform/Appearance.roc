import Host

## The system's appearance: whether it asks for a light or a dark scheme, and
## whether it asks for reduced motion. Adaptive colours follow the scheme
## without any of this; read it when an application decides something by it,
## such as whether to animate.
Appearance := [].{

	## The colour scheme the system asks for. A system with no preference is
	## `Light`.
	Scheme : [Light, Dark]

	## Whether the system asks for non-essential motion to be reduced. A system
	## that does not say is `Full`.
	Motion : [Full, Reduced]

	## The system's appearance, as the host last observed it.
	Settings : { scheme : Scheme, motion : Motion }

	## Which scheme adaptive colours resolve to: the system's, or one the
	## application chooses over it.
	Preference : [System, Light, Dark]

	## The system's appearance now.
	current! : () => Settings
	current! = || decode(Host.appearance_current!())

	## Wait until the system's appearance differs from `known` and return it.
	## Call from `Action.task`, with a key so a newer wait supersedes it:
	## cancelling the task interrupts the wait, which then returns `known`.
	next_change! : Settings => Settings
	next_change! = |known| decode(Host.appearance_next_change!(encode(known)))

	## Resolve adaptive colours by `preference` from now on. The window
	## repaints with the scheme it names; the application does not render
	## again. The choice lasts until the next `prefer!`, not across launches.
	prefer! : Preference => {}
	prefer! = |preference| Host.appearance_prefer!(
		match preference {
			System => 0
			Light => 1
			Dark => 2
		},
	)

	decode : U8 -> Settings
	decode = |bits| {
		scheme: if bits % 2 == 1 Dark else Light,
		motion: if (bits // 2) % 2 == 1 Reduced else Full,
	}

	encode : Settings -> U8
	encode = |settings| {
		scheme = match settings.scheme {
			Light => 0
			Dark => 1
		}
		motion = match settings.motion {
			Full => 0
			Reduced => 2
		}
		scheme + motion
	}
}

expect Appearance.decode(3) == { scheme: Dark, motion: Reduced }
expect Appearance.encode({ scheme: Light, motion: Reduced }) == 2
