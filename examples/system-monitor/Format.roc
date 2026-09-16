## Number and string shaping for a dense readout.
##
## Every figure a monitor prints is read against the one printed a moment ago,
## so the shaping here is about width as much as it is about value: one decimal
## everywhere, a unit chosen once per magnitude, and padding that puts a column
## of figures under its own heading.
Format := [].{
	## One decimal place from a value that is already scaled by ten. The sampler
	## reports CPU in tenths of a percent, and percentages derived from bytes are
	## computed in the same unit, so the application has one rounding rule.
	tenths : U64 -> Str
	tenths = tenths

	## A part of a whole, in tenths of one percent. A zero whole is nothing to be
	## a part of, so it reads as zero rather than dividing.
	share_tenths : U64, U64 -> U64
	share_tenths = share_tenths

	## A byte count split into the magnitude and the unit it was scaled by, so a
	## caller can set the two at different sizes and keep the figure dominant.
	## Binary multiples, named as such: a monitor that says GB when it divided by
	## 1024 is quietly wrong about the number beside it.
	Scaled : { unit : Str, value : Str }
	bytes : U64 -> Scaled
	bytes = bytes

	## A byte count as one string, for a log line where the unit travels with the
	## figure rather than sitting in its own slot.
	byte_text : U64 -> Str
	byte_text = byte_text

	## Right-align a figure inside `width` columns. Monospace plus a fixed width
	## is what stops a column of numbers shifting as its digits change.
	pad_left : Str, U64 -> Str
	pad_left = pad_left

	## Left-align a name inside `width` columns, so whatever follows it starts at
	## the same place on every row.
	pad_right : Str, U64 -> Str
	pad_right = pad_right

	## Shorten a name to `width` columns, ending it with a marker so a truncated
	## value never looks like a complete one. Splitting UTF-8 mid character would
	## produce an unencodable string, so the cut lands on a character boundary.
	truncate : Str, U64 -> Str
	truncate = truncate

	## The number of characters in a string, which is the number of columns it
	## occupies in a fixed-pitch face.
	count_chars : Str -> U64
	count_chars = count_chars
}

kib = 1024.U64
mib = 1048576.U64
gib = 1073741824.U64
tib = 1099511627776.U64

tenths = |value| "${(value / 10).to_str()}.${(value % 10).to_str()}"

share_tenths = |part, whole| if whole == 0 0 else part * 1000 / whole

bytes = |count| if count >= tib {
	{ unit: "TiB", value: tenths(count * 10 / tib) }
} else if count >= gib {
	{ unit: "GiB", value: tenths(count * 10 / gib) }
} else if count >= mib {
	{ unit: "MiB", value: tenths(count * 10 / mib) }
} else if count >= kib {
	{ unit: "KiB", value: tenths(count * 10 / kib) }
} else {
	{ unit: "B", value: count.to_str() }
}

byte_text = |count| {
	scaled = bytes(count)
	"${scaled.value} ${scaled.unit}"
}

count_chars = |text| {
	var $count = 0
	for byte in Str.to_utf8(text) {
		$count = if byte < 0x80 or byte >= 0xc0 $count + 1 else $count
	}
	$count
}

## How many columns short of `width` a string falls, never below zero.
deficit = |text, width| {
	occupied = count_chars(text)
	if occupied >= width 0 else width - occupied
}

spaces = |count| {
	var $out = ""
	var $remaining = count
	while $remaining > 0 {
		$out = "${$out} "
		$remaining = $remaining - 1
	}
	$out
}

pad_left = |text, width| "${spaces(deficit(text, width))}${text}"

pad_right = |text, width| "${text}${spaces(deficit(text, width))}"

truncate = |text, width| if width == 0 or count_chars(text) <= width {
	text
} else {
	utf8 = Str.to_utf8(text)
	var $seen = 0
	var $cut = 0
	var $index = 0
	for byte in utf8 {
		leads = byte < 0x80 or byte >= 0xc0
		$cut = if leads and $seen == width - 1 and $cut == 0 $index else $cut
		$seen = if leads $seen + 1 else $seen
		$index = $index + 1
	}
	"${Str.from_utf8(utf8.take_first($cut)) ?? text}…"
}

expect tenths(427.U64) == "42.7"
expect tenths(1000.U64) == "100.0"
expect share_tenths(6442450944.U64, 17179869184) == 375
expect share_tenths(1.U64, 0) == 0
expect bytes(512.U64) == { unit: "B", value: "512" }
expect bytes(17179869184.U64) == { unit: "GiB", value: "16.0" }
expect bytes(6442450944.U64) == { unit: "GiB", value: "6.0" }
expect byte_text(24576.U64) == "24.0 KiB"
expect pad_left("42.7", 6.U64) == "  42.7"
expect pad_left("overlong", 3.U64) == "overlong"
expect pad_right("init", 8.U64) == "init    "
expect count_chars("café") == 4
expect truncate("short", 8.U64) == "short"
expect truncate("systemsoundserverd", 8.U64) == "systems…"
expect truncate("cafécafé", 5.U64) == "café…"
