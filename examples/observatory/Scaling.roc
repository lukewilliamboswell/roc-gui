## A scaling set: captures of one executable at several benchmark scales, and
## how each trigger's work grows between them. Each capture is read through a
## connection of its own; the per-trigger means and the scale checks are
## queried here, beside the rules that judge them.
import pf.Gui
import Capture

## One trigger's mean work per measured cycle of the sample runs. Allocation
## bytes are over the cycles whose span evidence is valid, and absent when
## there are none.
Mean : { trigger : Str, cycles : I64, callback : I64, validate : I64, graph : I64, allocated : [None, Some(I64)] }

## The steps that assert a count, and those whose observed count differed.
Checks : { checks : I64, mismatches : I64 }

## One capture of a scaling set, or the A/A capture.
Member : { opened : Capture.Opened, means : List(Mean), checks : Checks }

## The captures chosen from the folder, and those read when the set was
## built. `read` is the request that built it.
Selection : { chosen : List(Str), members : List(Member), read : U64 }

## One gate key of a set.
Gate : { key : Str, pass : Bool, detail : Str }

Metric : [Callback, Validate, Graph, Allocated]

## One step from a scale to the next.
Step : { from : I64, to : I64, observed : [None, Some({ num : I64, den : I64 })], noise : [None, Some(Bool)] }

## One trigger and metric across the set. `verdict` is present only when
## every step's evidence is.
Row : { trigger : Str, metric : Metric, steps : List(Step), verdict : [None, Some(Str)], absence : Str }

Scaling := [].{
	Mean : Mean
	Checks : Checks
	Member : Member
	Selection : Selection
	Gate : Gate
	Metric : Metric
	Step : Step
	Row : Row

	empty : Selection
	empty = { chosen: [], members: [], read: 0 }

	## Open one capture of the folder and read its means and scale checks.
	load! : Gui.FilesDirRead, Str => Try(Member, Str)
	load! = load!

	## Every chosen capture, in the order chosen.
	load_all! : Gui.FilesDirRead, List(Str) => Try(List(Member), Str)
	load_all! = |directory, names| {
		var $members = []
		for name in names {
			member = load!(directory, name)?
			$members = $members.append(member)
		}
		Ok($members)
	}

	toggle : Selection, Str -> Selection
	toggle = |set, name| if set.chosen.contains(name) { ..set, chosen: set.chosen.keep_if(|found| found != name) } else { ..set, chosen: set.chosen.append(name) }

	scale : Member -> [None, Some(I64)]
	scale = scale

	## The gate, in words, exactly as `gate` applies it.
	rule : Str
	rule = "A scaling set is two or more finalised captures of one application and executable, on one backend, profile, OS, architecture, CPU, and detail, each timed in isolation with one job, at distinct benchmark scales."

	gate : List(Member) -> List(Gate)
	gate = gate

	## The first failing gate key, which refuses the set.
	refusal : List(Gate) -> [None, Some(Str)]
	refusal = |checks| match checks.find_first(|found| !found.pass) {
		Ok(found) => Some("${found.key}: ${found.detail}")
		Err(_) => None
	}

	## Members ordered by scale.
	ordered : List(Member) -> List(Member)
	ordered = ordered

	metrics : List(Metric)
	metrics = [Callback, Validate, Graph, Allocated]

	metric_name : Metric -> Str
	metric_name = metric_name

	## The verdict rule, in words, exactly as `classify` applies it.
	verdict_rule : Str
	verdict_rule = "Over the whole set, an observed ratio r against a scale ratio s is linear when s^0.8 ≤ r ≤ s^1.2, sub-linear below, and super-linear above. A verdict needs every step's evidence complete."

	## The A/A rule for a ratio, in words, exactly as `rows` applies it.
	noise_rule : Str
	noise_rule = "The A/A band of a trigger and metric is how far the A/A capture's mean lies from the set member of its scale, as a fraction of it. A step ratio r within that fraction of 1 is within noise."

	classify : { num : I64, den : I64 }, { num : I64, den : I64 } -> Str
	classify = classify

	## Every trigger present in all members, by metric. `noise` is the A/A
	## capture, already accepted against the member of its scale.
	rows : List(Member), [None, Some(Member)] -> List(Row)
	rows = rows

	## One member's mean of a metric for a trigger, when its families are
	## complete.
	value : Member, Str, Metric -> [None, Some(I64)]
	value = |member, trigger, metric| if !complete_for(member, metric) {
		None
	} else {
		match mean_of(member, trigger) {
			Some(mean) => value_of(metric, mean)
			None => None
		}
	}

	## A ratio as `9.6×`.
	ratio_text : { num : I64, den : I64 } -> Str
	ratio_text = ratio_text
}

## Sample runs only, and measured cycles only: the benchmark's own work.
means_sql = "WITH m AS (SELECT c.id, c.trigger, c.roc_callback_ns, c.validate_ns, c.graph_apply_ns, c.roc_work_valid FROM cycles c JOIN runs r ON r.id = c.run_id WHERE r.phase = 'sample' AND c.measurement_phase = 'measured'), a AS (SELECT m.trigger, count(DISTINCT m.id) AS valid, coalesce(sum(s.allocated_bytes), 0) AS bytes FROM m LEFT JOIN roc_work_spans s ON s.cycle_id = m.id WHERE m.roc_work_valid = 1 GROUP BY m.trigger) SELECT m.trigger, count(*), CAST(round(avg(m.roc_callback_ns)) AS INTEGER), CAST(round(avg(m.validate_ns)) AS INTEGER), CAST(round(avg(m.graph_apply_ns)) AS INTEGER), CASE WHEN a.valid > 0 THEN CAST(round(a.bytes * 1.0 / a.valid) AS INTEGER) END FROM m LEFT JOIN a ON a.trigger = m.trigger GROUP BY m.trigger ORDER BY m.trigger"

## A count assertion of any run but a warmup, and whether it held.
checks_sql = "SELECT count(*), coalesce(sum(CASE WHEN s.observed_count IS s.expected_count THEN 0 ELSE 1 END), 0) FROM steps s JOIN runs r ON r.id = s.run_id WHERE r.phase <> 'warmup' AND s.expected_count IS NOT NULL"

int_at : List(Gui.SqliteValue), U64 -> I64
int_at = |row, index| match row.get(index) {
	Ok(Integer(value)) => value
	_ => 0
}

load! : Gui.FilesDirRead, Str => Try(Member, Str)
load! = |directory, name| {
	opened = Capture.open!(directory, name)?
	found = opened.database.query!(means_sql) ? |error| Gui.Sqlite.detail(error)
	counted = opened.database.query!(checks_sql) ? |error| Gui.Sqlite.detail(error)
	means = found.rows.map(
		|row| {
			trigger: match row.get(0) {
				Ok(String(text)) => text
				_ => ""
			},
			cycles: int_at(row, 1),
			callback: int_at(row, 2),
			validate: int_at(row, 3),
			graph: int_at(row, 4),
			allocated: match row.get(5) {
				Ok(Integer(value)) => Some(value)
				_ => None
			},
		},
	)
	checks = match counted.rows.first() {
		Ok(row) => { checks: int_at(row, 0), mismatches: int_at(row, 1) }
		Err(_) => { checks: 0, mismatches: 0 }
	}
	Ok({ opened, means, checks })
}

scale : Member -> [None, Some(I64)]
scale = |member| match I64.from_str(Capture.metadata(member.opened, "benchmark_scale")) {
	Ok(value) if value > 0 => Some(value)
	_ => None
}

scale_or_zero : Member -> I64
scale_or_zero = |member| match scale(member) {
	Some(value) => value
	None => 0
}

ordered : List(Member) -> List(Member)
ordered = |members| List.sort_with(
	members,
	|a, b| {
		left = scale_or_zero(a)
		right = scale_or_zero(b)
		if left < right Before else if left > right After else Same
	},
)

## Keys every member must share with the first.
shared_keys : List(Str)
shared_keys = ["app_name", "executable_hash", "backend", "target_profile", "host_os", "host_arch", "cpu_model", "logical_cpu_count", "requested_detail"]

## A key every member must pass, failing at the first member that does not.
each : List(Member), Str, (Member -> [Pass, Fail(Str)]) -> Gate
each = |members, key, judge| {
	var $found = { key, pass: True, detail: "" }
	for member in members {
		if $found.pass {
			match judge(member) {
				Fail(detail) => {
					$found = { key, pass: False, detail: "${member.opened.name} ${detail}" }
				}
				Pass => {}
			}
		}
	}
	$found
}

gate : List(Member) -> List(Gate)
gate = |members| {
	value = |member, key| Capture.metadata(member.opened, key)
	count = { key: "members", pass: members.len() >= 2, detail: if members.len() >= 2 "" else "a set needs two or more captures, not ${members.len().to_str()}" }
	finalised = each(
		members,
		"final_state",
		|member| if value(member, "final_state") != "complete" Fail("is a ${Capture.unfinalised}") else if value(member, "clean_shutdown") == "1" Pass else Fail("did not shut down cleanly"),
	)
	shared = match members.first() {
		Err(_) => []
		Ok(first) => shared_keys.map(
			|key| each(
				members,
				key,
				|member| {
					mine = value(member, key)
					theirs = value(first, key)
					if Str.is_empty(mine) or mine == "unavailable" Fail("has no ${key}") else if mine == theirs Pass else Fail("has ${mine}, ${first.opened.name} has ${theirs}")
				},
			),
		)
	}
	isolated = each(members, "timing_quality", |member| if value(member, "timing_quality") == "isolated" Pass else Fail("is ${value(member, "timing_quality")}; a scaling set needs isolated timing"))
	jobs = each(members, "job_count", |member| if value(member, "job_count") == "1" Pass else Fail("ran ${value(member, "job_count")} jobs; a scaling set needs 1"))
	scales = members.map(scale)
	distinct = each(
		members,
		"benchmark_scale",
		|member| match scale(member) {
			None => Fail("records no benchmark scale")
			Some(own) => if scales.keep_if(|found| found == Some(own)).len() > 1 Fail("shares scale ${own.to_str()} with another capture") else Pass
		},
	)
	[count, finalised].concat(shared).concat([isolated, jobs, distinct])
}

metric_name : Metric -> Str
metric_name = |metric| match metric {
	Callback => "callback"
	Validate => "validate"
	Graph => "graph apply"
	Allocated => "span allocated bytes"
}

## A metric's families, and its value in one trigger's mean.
families : Metric -> List(Str)
families = |metric| match metric {
	Allocated => ["roc_work_spans", "roc_allocations"]
	_ => ["host_cycles"]
}

value_of : Metric, Mean -> [None, Some(I64)]
value_of = |metric, mean| match metric {
	Callback => Some(mean.callback)
	Validate => Some(mean.validate)
	Graph => Some(mean.graph)
	Allocated => mean.allocated
}

mean_of : Member, Str -> [None, Some(Mean)]
mean_of = |member, trigger| match member.means.find_first(|found| found.trigger == trigger) {
	Ok(found) => Some(found)
	Err(_) => None
}

complete_for : Member, Metric -> Bool
complete_for = |member, metric| families(metric).all(|name| Capture.complete(member.opened, name))

## `r^5` against `s^4` and `s^6`, in thousandths and 128 bits, so the
## exponent bounds 0.8 and 1.2 need no logarithm.
classify : { num : I64, den : I64 }, { num : I64, den : I64 } -> Str
classify = |observed, scaled| {
	milli = |fraction| {
		raw = fraction.num.to_i128() * 1000 / fraction.den.to_i128()
		if raw > 1000000 1000000 else if raw < 1 1 else raw
	}
	r = milli(observed)
	s = milli(scaled)
	thousand = 1000.I128
	r5 = r * r * r * r * r
	if r5 < s * s * s * s * thousand {
		"sub-linear"
	} else if r5 * thousand > s * s * s * s * s * s {
		"super-linear"
	} else {
		"linear"
	}
}

expect classify({ num: 96, den: 10 }, { num: 10, den: 1 }) == "linear"
expect classify({ num: 31, den: 1 }, { num: 10, den: 1 }) == "super-linear"
expect classify({ num: 11, den: 10 }, { num: 10, den: 1 }) == "sub-linear"
expect classify({ num: 100, den: 1 }, { num: 100, den: 1 }) == "linear"

ratio_text : { num : I64, den : I64 } -> Str
ratio_text = |fraction| if fraction.den <= 0 {
	"—"
} else {
	tenths = fraction.num * 10 / fraction.den
	"${(tenths / 10).to_str()}.${(tenths % 10).to_str()}×"
}

expect ratio_text({ num: 96, den: 10 }) == "9.6×"

## How far `twin` lies from `base`, in thousandths of `base`.
band : I64, I64 -> [None, Some(I64)]
band = |base, twin| if base <= 0 None else Some((if twin > base twin - base else base - twin) * 1000 / base)

row_for : List(Member), [None, Some(Member)], Str, Metric -> Row
row_for = |members, noise, trigger, metric| {
	complete = members.all(|member| complete_for(member, metric))
	values : List({ at : I64, value : [None, Some(I64)] })
	values = members.map(
		|member| {
			at: scale_or_zero(member),
			value: match mean_of(member, trigger) {
				Some(mean) => value_of(metric, mean)
				None => None
			},
		},
	)
	bound = match noise {
		Some(twin) if complete_for(twin, metric) => {
			twin_scale = scale(twin)
			match (members.find_first(|member| scale(member) == twin_scale), mean_of(twin, trigger)) {
				(Ok(member), Some(twin_mean)) => match (mean_of(member, trigger), value_of(metric, twin_mean)) {
					(Some(own), Some(twin_value)) => match value_of(metric, own) {
						Some(own_value) => band(own_value, twin_value)
						None => None
					}
					_ => None
				}
				_ => None
			}
		}
		_ => None
	}
	steps = List.map2(
		values.drop_last(1),
		values.drop_first(1),
		|a, b| {
			observed = match (a.value, b.value) {
				(Some(x), Some(y)) if complete and x > 0 => Some({ num: y, den: x })
				_ => None
			}
			noise_mark = match (observed, bound) {
				(Some(fraction), Some(limit)) => {
					deviation = fraction.num * 1000 / fraction.den - 1000
					Some((if deviation < 0 -deviation else deviation) <= limit)
				}
				_ => None
			}
			{ from: a.at, to: b.at, observed, noise: noise_mark }
		},
	)
	verdict = match (values.first(), values.last()) {
		(Ok(low), Ok(high)) => match (low.value, high.value) {
			(Some(x), Some(y)) if complete and x > 0 and low.at > 0 and steps.all(|step| step.observed != None) => Some(classify({ num: y, den: x }, { num: high.at, den: low.at }))
			_ => None
		}
		_ => None
	}
	absence = if !complete {
		missing = families(metric).keep_if(|name| !members.all(|member| Capture.complete(member.opened, name)))
		"${Str.join_with(missing, ", ")} is not complete in every capture"
	} else if verdict == None {
		"a zero or absent mean leaves a step without a ratio"
	} else {
		""
	}
	{ trigger, metric, steps, verdict, absence }
}

rows : List(Member), [None, Some(Member)] -> List(Row)
rows = |members, noise| {
	sorted = ordered(members)
	triggers = match sorted.first() {
		Ok(first) => first.means.map(|mean| mean.trigger).keep_if(|trigger| sorted.all(|member| mean_of(member, trigger) != None))
		Err(_) => []
	}
	triggers.fold([], |found, trigger| found.concat([Callback, Validate, Graph, Allocated].map(|metric| row_for(sorted, noise, trigger, metric))))
}
