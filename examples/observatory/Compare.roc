## Whether two captures may be compared, and what a baseline adds to a value.
## Every rule is stated here, beside the keys it reads, and in the words the
## Compare view shows: a pair is comparable only when every gate key passes,
## and an incomparable pair shows its reasons and no delta anywhere.
import Capture

## How a gate key passes: the two captures agree, or both hold one value.
Rule : [Same, Both(Str)]

## One gate key, both values, and why it failed if it did.
Check : { key : Str, a : Str, b : Str, pass : Bool, reason : Str }

## The comparison a view applies. `Refused` carries the failing keys, and no
## view shows a delta for it. `On` carries the A/A capture when one was chosen
## and accepted, or why the chosen one was refused.
Mode : [
	Off,
	Refused({ baseline : Capture.Opened, reasons : List(Str) }),
	On({ baseline : Capture.Opened, noise : [None, Some(Capture.Opened)], noise_refused : [None, Some(Str)] }),
]

## A value against the baseline's. `bound` is the A/A spread of the same value
## when an A/A capture is applied.
Delta : { value : I64, base : I64, delta : I64, bound : [None, Some(I64)] }

Compare := [].{
	Rule : Rule
	Check : Check
	Mode : Mode
	Delta : Delta

	## Every key the comparability gate reads, in the order the sheet lists
	## them: schema and finalisation, the specification and its benchmark
	## settings, then the environment the timing depends on.
	gate : List({ key : Str, rule : Rule })
	gate = gate

	## The gate, in words, exactly as `sheet` applies it.
	rule : Str
	rule = "Comparable when both captures are schema 19, finalised, and shut down cleanly, and they agree on every other key. A key absent or unavailable in either capture fails: missing identity is never guessed."

	## The A/A rule, in words, exactly as `accept_noise` applies it.
	noise_rule : Str
	noise_rule = "An A/A capture is the same executable run again: it must pass the comparability gate against the capture it bounds and name the same executable_hash."

	sheet : Capture.Opened, Capture.Opened -> List(Check)
	sheet = sheet

	failures : List(Check) -> List(Str)
	failures = failures

	## The comparison a capture shows against a baseline and an A/A capture.
	mode : [None, Some(Capture.Opened)], [None, Some(Capture.Opened)], [None, Some(Capture.Opened)] -> Mode
	mode = mode

	## Why an A/A capture cannot bound a reference capture, if it cannot.
	accept_noise : Capture.Opened, Capture.Opened -> Try({}, Str)
	accept_noise = accept_noise

	## A trigger group against the baseline's group of the same phase,
	## trigger, and patch kind, by median. Absent when either capture's cycle
	## timing is not complete or the baseline has no such group.
	trigger_delta : Mode, Capture.Opened, Capture.Trigger -> [Hidden, Absent(Str), Shown(Delta)]
	trigger_delta = trigger_delta

	## One cycle against the median of its trigger group in the baseline.
	cycle_delta : Mode, Capture.Opened, Capture.Cycle -> [Hidden, Absent(Str), Shown(Delta)]
	cycle_delta = cycle_delta

	## A trigger's mean allocated bytes in one span against the baseline's.
	allocation_delta : Mode, Capture.Opened, Capture.TriggerAlloc -> [Hidden, Absent(Str), Shown(Delta)]
	allocation_delta = allocation_delta

	## The size of a delta, for ordering by |Δ|; a hidden or absent one sorts
	## last.
	magnitude : [Hidden, Absent(Str), Shown(Delta)] -> I64
	magnitude = |found| match found {
		Shown(delta) => if delta.delta < 0 -delta.delta else delta.delta
		_ => -1
	}

	## A delta inside its A/A bound.
	within_noise : Delta -> [None, Some(Bool)]
	within_noise = within_noise

	## `b` over `a` as a ratio with two decimals.
	ratio : I64, I64 -> Str
	ratio = ratio

	signed_ms : I64 -> Str
	signed_ms = signed_ms

	signed_bytes : I64 -> Str
	signed_bytes = signed_bytes
}

gate : List({ key : Str, rule : Rule })
gate = [
	{ key: "schema_version", rule: Both(Capture.supported_schema) },
	{ key: "final_state", rule: Both("complete") },
	{ key: "clean_shutdown", rule: Both("1") },
	{ key: "spec_hash", rule: Same },
	{ key: "benchmark_scale", rule: Same },
	{ key: "benchmark_samples", rule: Same },
	{ key: "benchmark_iterations", rule: Same },
	{ key: "benchmark_initial_size", rule: Same },
	{ key: "benchmark_change_size", rule: Same },
	{ key: "backend", rule: Same },
	{ key: "target_profile", rule: Same },
	{ key: "host_os", rule: Same },
	{ key: "host_arch", rule: Same },
	{ key: "cpu_model", rule: Same },
	{ key: "logical_cpu_count", rule: Same },
	{ key: "requested_detail", rule: Same },
	{ key: "job_count", rule: Same },
	{ key: "buffer_mib", rule: Same },
	{ key: "timing_quality", rule: Same },
]

absent : Str -> Bool
absent = |value| Str.is_empty(value) or value == "unavailable"

check : Str, Rule, Str, Str -> Check
check = |key, rule, a, b| {
	failed = |reason| { key, a, b, pass: False, reason }
	if absent(a) {
		failed("${key} is absent from A")
	} else if absent(b) {
		failed("${key} is absent from B")
	} else {
		match rule {
			Same => if a == b { key, a, b, pass: True, reason: "" } else failed("${key} differs: ${a} against ${b}")
			Both(required) => if a == required and b == required { key, a, b, pass: True, reason: "" } else failed("${key} must be ${required} in both")
		}
	}
}

sheet : Capture.Opened, Capture.Opened -> List(Check)
sheet = |a, b| gate.map(|entry| check(entry.key, entry.rule, Capture.metadata(a, entry.key), Capture.metadata(b, entry.key)))

failures : List(Check) -> List(Str)
failures = |checks| checks.keep_if(|found| !found.pass).map(|found| found.reason)

accept_noise : Capture.Opened, Capture.Opened -> Try({}, Str)
accept_noise = |reference, noise| {
	failed = failures(sheet(reference, noise))
	match failed.first() {
		Ok(reason) => Err(reason)
		Err(_) => {
			same = check("executable_hash", Same, Capture.metadata(reference, "executable_hash"), Capture.metadata(noise, "executable_hash"))
			if same.pass Ok({}) else Err(same.reason)
		}
	}
}

mode : [None, Some(Capture.Opened)], [None, Some(Capture.Opened)], [None, Some(Capture.Opened)] -> Mode
mode = |capture, baseline, noise| match (capture, baseline) {
	(Some(opened), Some(base)) => {
		reasons = failures(sheet(base, opened))
		if !reasons.is_empty() {
			Refused({ baseline: base, reasons })
		} else {
			match noise {
				None => On({ baseline: base, noise: None, noise_refused: None })
				Some(twin) => match accept_noise(base, twin) {
					Ok({}) => On({ baseline: base, noise: Some(twin), noise_refused: None })
					Err(reason) => On({ baseline: base, noise: None, noise_refused: Some(reason) })
				}
			}
		}
	}
	_ => Off
}

same_group : Capture.Trigger, Capture.Trigger -> Bool
same_group = |a, b| a.phase == b.phase and a.trigger == b.trigger and a.patch_kind == b.patch_kind

group_in : Capture.Opened, Capture.Trigger -> [None, Some(Capture.Trigger)]
group_in = |opened, trigger| match opened.triggers.find_first(|found| same_group(found, trigger)) {
	Ok(found) => Some(found)
	Err(_) => None
}

## The A/A spread of a value: how far the A/A capture's value lies from the
## baseline's.
spread : I64, I64 -> I64
spread = |base, twin| if twin > base twin - base else base - twin

timed_delta : Mode, Capture.Opened, Capture.Trigger, I64 -> [Hidden, Absent(Str), Shown(Delta)]
timed_delta = |current, opened, group, value| match current {
	On(applied) => {
		timed = Capture.complete(opened, "host_cycles") and Capture.complete(applied.baseline, "host_cycles")
		if !timed {
			Absent("host_cycles is not complete in both captures")
		} else {
			match group_in(applied.baseline, group) {
				None => Absent("the baseline has no ${group.trigger} ${group.patch_kind} cycles in the ${group.phase} phase")
				Some(base) => {
					bound = match applied.noise {
						Some(twin) if Capture.complete(twin, "host_cycles") => match group_in(twin, group) {
							Some(found) => Some(spread(base.median, found.median))
							None => None
						}
						_ => None
					}
					Shown({ value, base: base.median, delta: value - base.median, bound })
				}
			}
		}
	}
	_ => Hidden
}

trigger_delta : Mode, Capture.Opened, Capture.Trigger -> [Hidden, Absent(Str), Shown(Delta)]
trigger_delta = |current, opened, group| timed_delta(current, opened, group, group.median)

cycle_delta : Mode, Capture.Opened, Capture.Cycle -> [Hidden, Absent(Str), Shown(Delta)]
cycle_delta = |current, opened, cycle| {
	group = { phase: cycle.phase, trigger: cycle.trigger, patch_kind: cycle.patch_kind, count: 0, min: 0, median: 0, max: 0, iqr: 0 }
	timed_delta(current, opened, group, cycle.duration)
}

same_allocation : Capture.TriggerAlloc, Capture.TriggerAlloc -> Bool
same_allocation = |a, b| a.phase == b.phase and a.trigger == b.trigger and a.span == b.span

allocation_in : Capture.Opened, Capture.TriggerAlloc -> [None, Some(Capture.TriggerAlloc)]
allocation_in = |opened, row| match opened.allocations.find_first(|found| same_allocation(found, row)) {
	Ok(found) => Some(found)
	Err(_) => None
}

allocation_delta : Mode, Capture.Opened, Capture.TriggerAlloc -> [Hidden, Absent(Str), Shown(Delta)]
allocation_delta = |current, opened, row| match current {
	On(applied) => {
		if !(Capture.complete(opened, "roc_work_spans") and Capture.complete(applied.baseline, "roc_work_spans")) {
			Absent("roc_work_spans is not complete in both captures")
		} else {
			match allocation_in(applied.baseline, row) {
				None => Absent("the baseline has no ${row.trigger} ${row.span} allocations")
				Some(base) => {
					bound = match applied.noise {
						Some(twin) if Capture.complete(twin, "roc_work_spans") => match allocation_in(twin, row) {
							Some(found) => Some(spread(base.bytes_mean, found.bytes_mean))
							None => None
						}
						_ => None
					}
					Shown({ value: row.bytes_mean, base: base.bytes_mean, delta: row.bytes_mean - base.bytes_mean, bound })
				}
			}
		}
	}
	_ => Hidden
}

within_noise : Delta -> [None, Some(Bool)]
within_noise = |found| match found.bound {
	Some(bound) => Some((if found.delta < 0 -found.delta else found.delta) <= bound)
	None => None
}

## Hundredths, rounded toward zero.
hundredths : I64 -> Str
hundredths = |value| {
	fraction = value % 100
	"${(value / 100).to_str()}.${if fraction < 10 "0" else ""}${fraction.to_str()}"
}

ratio : I64, I64 -> Str
ratio = |b, a| if a <= 0 or b < 0 "—" else "${hundredths(b * 100 / a)}×"

signed_ms : I64 -> Str
signed_ms = |ns| {
	micros = (if ns < 0 -ns else ns) / 1000
	fraction = micros % 1000
	padding = if fraction < 10 "00" else if fraction < 100 "0" else ""
	"${if ns < 0 "−" else "+"}${(micros / 1000).to_str()}.${padding}${fraction.to_str()} ms"
}

signed_bytes : I64 -> Str
signed_bytes = |count| {
	size = if count < 0 -count else count
	sign = if count < 0 "−" else "+"
	if size >= 1024 {
		tenths = size * 10 / 1024
		"${sign}${(tenths / 10).to_str()}.${(tenths % 10).to_str()} KiB"
	} else {
		"${sign}${size.to_str()} B"
	}
}

expect ratio(92, 100) == "0.92×"
expect ratio(1000, 100) == "10.00×"
expect ratio(5, 0) == "—"
expect signed_ms(-40000) == "−0.040 ms"
expect signed_ms(1250000) == "+1.250 ms"
expect signed_bytes(2048) == "+2.0 KiB"
expect signed_bytes(-10) == "−10 B"
expect check("job_count", Same, "1", "2") == { key: "job_count", a: "1", b: "2", pass: False, reason: "job_count differs: 1 against 2" }
expect check("final_state", Both("complete"), "complete", "recording").pass == False
expect check("cpu_model", Same, "unavailable", "unavailable").reason == "cpu_model is absent from A"
expect within_noise({ value: 10, base: 12, delta: -2, bound: Some(3) }) == Some(True)
expect within_noise({ value: 10, base: 15, delta: -5, bound: Some(3) }) == Some(False)
