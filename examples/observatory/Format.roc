## Number shaping for measurements. Durations are recorded in nanoseconds and
## shown in milliseconds with three decimals, so a column of them lines up.
Format := [].{

	## Nanoseconds as milliseconds, truncated to the microsecond.
	ms : I64 -> Str
	ms = ms

	## An optional measurement. Absent is `—`, never zero.
	maybe_ms : [None, Some(I64)] -> Str
	maybe_ms = |value| match value {
		Some(ns) => ms(ns)
		None => "—"
	}

	maybe_int : [None, Some(I64)] -> Str
	maybe_int = |value| match value {
		Some(number) => number.to_str()
		None => "—"
	}

	## A byte count in binary units with one decimal.
	bytes : I64 -> Str
	bytes = bytes

	## A part of a whole as a whole percentage. A zero whole is nothing to be a
	## part of.
	percent : I64, I64 -> Str
	percent = |part, whole| if whole == 0 "—" else "${(part * 100 / whole).to_str()}%"
}

ms : I64 -> Str
ms = |ns| {
	micros = ns / 1000
	whole = micros / 1000
	fraction = micros % 1000
	padding = if fraction < 10 "00" else if fraction < 100 "0" else ""
	"${whole.to_str()}.${padding}${fraction.to_str()} ms"
}

tenths : I64 -> Str
tenths = |value| "${(value / 10).to_str()}.${(value % 10).to_str()}"

bytes : I64 -> Str
bytes = |count| if count >= 1048576 {
	"${tenths(count * 10 / 1048576)} MiB"
} else if count >= 1024 {
	"${tenths(count * 10 / 1024)} KiB"
} else {
	"${count.to_str()} B"
}

expect ms(530000) == "0.530 ms"
expect ms(12345678) == "12.345 ms"
expect bytes(159744) == "156.0 KiB"
