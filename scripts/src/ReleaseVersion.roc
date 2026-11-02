## Release version selection without filesystem or network effects.
ReleaseVersion := [].{
	Version : { major : Str, minor : Str, patch : Str, suffix : Str }
	parse : Str -> Try(Version, [InvalidVersion])
	parse = |text| {
		parts = text.split_on("-")
		(core, suffix) = match parts {
			[only] => (only, "")
			[first, .. as rest] if !rest.is_empty() => (first, Str.join_with(rest, "-"))
			_ => return Err(InvalidVersion)
		}
		if (parts.len() > 1 and suffix == "") or (suffix != "" and !suffix.split_on(".").all(identifier)) {
			return Err(InvalidVersion)
		}
		match core.split_on(".") {
			[a, b, c] => Ok({ major: number(a)?, minor: number(b)?, patch: number(c)?, suffix })
			_ => Err(InvalidVersion)
		}
	}
	compare : Version, Version -> [Before, Same, After]
	compare = |a, b| {
		if a.major != b.major {
			return compare_number(a.major, b.major)
		}
		if a.minor != b.minor {
			return compare_number(a.minor, b.minor)
		}
		if a.patch != b.patch {
			return compare_number(a.patch, b.patch)
		}
		if a.suffix == b.suffix {
			return Same
		}
		if a.suffix == "" {
			return After
		}
		if b.suffix == "" {
			return Before
		}
		compare_suffix(a.suffix.split_on("."), b.suffix.split_on("."))
	}
}

number : Str -> Try(Str, [InvalidVersion])
number = |text| {
	if text == "" or (text.starts_with("0") and text != "0") or !text.to_utf8().all(|b| b >= '0' and b <= '9') {
		return Err(InvalidVersion)
	}
	Ok(text)
}

identifier : Str -> Bool
identifier = |text| text != "" and text.to_utf8().all(|b| (b >= '0' and b <= '9') or (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '-') and (!text.to_utf8().all(|b| b >= '0' and b <= '9') or (text == "0" or !text.starts_with("0")))

compare_suffix : List(Str), List(Str) -> [Before, Same, After]
compare_suffix = |a, b| match (a, b) {
	([], []) => Same
	([], _) => Before
	(_, []) => After
	([x, .. as xs], [y, .. as ys]) => if (x == y) compare_suffix(xs, ys) else {
		x_number = x.to_utf8().all(|byte| byte >= '0' and byte <= '9')
		y_number = y.to_utf8().all(|byte| byte >= '0' and byte <= '9')
		if (x_number and y_number) compare_number(x, y) else if (x_number) Before else if (y_number) After else compare_bytes(x.to_utf8(), y.to_utf8())
	}

}

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b| match (a, b) {
	([], []) => Same
	([], _) => Before
	(_, []) => After
	([x, .. as xs], [y, .. as ys]) => if (x == y) compare_bytes(xs, ys) else if (x < y) Before else After
}
expect ReleaseVersion.parse("01.2.3").is_err()
expect ReleaseVersion.parse("1.2.3-01").is_err()
expect ReleaseVersion.parse("1.2.3-rc.1").is_ok()
expect ReleaseVersion.parse("1.2.3-rc..1").is_err()
expect ReleaseVersion.compare(ReleaseVersion.parse("1.2.3-rc.2") ?? crash "version", ReleaseVersion.parse("1.2.3-rc.10") ?? crash "version") == Before
expect ReleaseVersion.compare(ReleaseVersion.parse("1.2.3-rc.10") ?? crash "version", ReleaseVersion.parse("1.2.3") ?? crash "version") == Before

compare_number : Str, Str -> [Before, Same, After]
compare_number = |a, b| if a.to_utf8().len() != b.to_utf8().len() {
	if (a.to_utf8().len() < b.to_utf8().len()) Before else After
} else compare_bytes(a.to_utf8(), b.to_utf8())
expect ReleaseVersion.parse("1.2.3-rc-").is_ok()
expect ReleaseVersion.parse("1.2.3-").is_err()
expect ReleaseVersion.parse("1.2.3-9999999999999999999999999").is_ok()
expect ReleaseVersion.compare(ReleaseVersion.parse("1.2.3-9999999999999999999999999") ?? crash "version", ReleaseVersion.parse("1.2.3-10000000000000000000000000") ?? crash "version") == Before
