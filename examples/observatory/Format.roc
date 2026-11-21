## Number shaping for measurements. Durations are recorded in nanoseconds and
## shown in milliseconds with three decimals, so a column of them lines up.
Format := [].{

	## Text in the order of its bytes, as every sortable column orders it.
	compare_text : Str, Str -> [Before, Same, After]
	compare_text = compare_text_impl

	## Nanoseconds as milliseconds, truncated to the microsecond.
	ms : I64 -> Str
	ms = ms_impl

	## An optional measurement. Absent is `—`, never zero.
	maybe_ms : [None, Some(I64)] -> Str
	maybe_ms = |value| match value {
		Some(ns) => ms_impl(ns)
		None => "—"
	}

	maybe_int : [None, Some(I64)] -> Str
	maybe_int = |value| match value {
		Some(number) => number.to_str()
		None => "—"
	}

	## A byte count in binary units with one decimal.
	bytes : I64 -> Str
	bytes = bytes_impl

	## A part of a whole as a whole percentage. A zero whole is nothing to be a
	## part of.
	percent : I64, I64 -> Str
	percent = |part, whole| if whole == 0 "—" else "${(part * 100 / whole).to_str()}%"
}

## A negative duration is a remainder that does not balance, and keeps its sign.
ms_impl : I64 -> Str
ms_impl = |ns| if ns < 0 "-${magnitude_ms(-ns)}" else magnitude_ms(ns)

magnitude_ms : I64 -> Str
magnitude_ms = |ns| {
	micros = ns / 1000
	whole = micros / 1000
	fraction = micros % 1000
	padding = if fraction < 10 "00" else if fraction < 100 "0" else ""
	"${whole.to_str()}.${padding}${fraction.to_str()} ms"
}

tenths : I64 -> Str
tenths = |value| "${(value / 10).to_str()}.${(value % 10).to_str()}"

bytes_impl : I64 -> Str
bytes_impl = |count| if count >= 1048576 {
	"${tenths(count * 10 / 1048576)} MiB"
} else if count >= 1024 {
	"${tenths(count * 10 / 1024)} KiB"
} else {
	"${count.to_str()} B"
}

expect ms_impl(530000) == "0.530 ms"
expect ms_impl(12345678) == "12.345 ms"
expect ms_impl(-250000) == "-0.250 ms"
expect bytes_impl(159744) == "156.0 KiB"

compare_text_impl : Str, Str -> [Before, Same, After]
compare_text_impl = |left, right| {
	left_bytes = left.to_utf8()
	right_bytes = right.to_utf8()
	var $result = Same
	for item in List.map2(left_bytes, right_bytes, |a, b| if a < b Before else if a > b After else Same) {
		if $result == Same {
			$result = item
		}
	}
	if $result == Same {
		if left_bytes.len() < right_bytes.len() Before else if left_bytes.len() > right_bytes.len() After else Same
	} else {
		$result
	}
}
