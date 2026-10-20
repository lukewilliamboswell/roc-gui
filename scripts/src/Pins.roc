## Which compiler each Roc root is written for, read from text without running
## one. Adapted from roc-automation's scripts/src/Pins.roc.
Pins := [].{

	## The nightly tag that the text of `Blueprint.roc` fetches as `roc-stable`.
	stable_tag : Str -> Try(Str, [NoStableCompiler])
	stable_tag = |blueprint|
		match Str.split_on(blueprint, "Fetch(\"roc-stable\", Recipes.roc_nightly(\"") {
			[_, after] =>
				match Str.split_first(after, "\"") {
					Ok({ before, .. }) if before != "" => Ok(before)
					_ => Err(NoStableCompiler)
				}
			_ => Err(NoStableCompiler)
		}

	## Whether `source` is an application, which has an `app` header.
	is_app : Str -> Bool
	is_app = |source| header(Str.split_on(source, "\n")) != ""

	## The release named by the `roc` field of an app header.
	roc_pin : Str -> Try(Str, [NoPin])
	roc_pin = |source|
		match header_field(source, "roc") {
			Ok(value) => quoted(value).map_err(|_| NoPin)
			Err(_) => Err(NoPin)
		}

	## The platform an app header depends on, as written.
	platform_of : Str -> Try(Str, [NoPlatform])
	platform_of = |source|
		match header_field(source, "pf") {
			Ok(value) if value.starts_with("platform ") => quoted(Str.drop_prefix(value, "platform ")).map_err(|_| NoPlatform)
			_ => Err(NoPlatform)
		}
}

# The one value of a header field named `name`, trimmed.
header_field : Str, Str -> Try(Str, [Missing])
header_field = |source, name| {
	fields = match Str.split_first(header(Str.split_on(source, "\n")), "{") {
		Ok({ after, .. }) => Str.split_on(after, ",")
		Err(_) => []
	}
	match fields.keep_oks(|field| Str.split_first(field, ":")).keep_if(|field| field.before.trim() == name) {
		[{ after, .. }] => Ok(after.trim())
		_ => Err(Missing)
	}
}

# The text between a value's only pair of double quotes.
quoted : Str -> Try(Str, [NotQuoted])
quoted = |value|
	match Str.split_on(value.trim(), "\"") {
		["", text, ""] => Ok(text)
		_ => Err(NotQuoted)
	}

# The app header, from `app` up to the brace that closes it. A module has none.
header : List(Str) -> Str
header = |lines|
	match lines {
		[line, ..] if line.starts_with("app ") =>
			match Str.split_first(Str.join_with(lines, "\n"), "}") {
				Ok({ before, .. }) => before
				Err(_) => ""
			}
		[_, .. as rest] => header(rest)
		[] => ""
	}

script : Str
script = "#!/usr/bin/env roc-stable\napp [main!] {\n\tcli: platform \"https://example.com/cli.tar.zst\",\n\troc: \"nightly-2026-10-18-1df370f\",\n}\n\nmain! = |_| { roc: \"not a header\" }\n"

example : Str
example = "app [State, main] {\n\tpf: platform \"../../platform/main.roc\",\n\tredis: \"https://example.com/redis.tar.zst\",\n}\n"

expect Pins.stable_tag("\t\tPrograms([Fetch(\"roc-stable\", Recipes.roc_nightly(\"nightly-2026-10-18-1df370f\"))]),\n") == Ok("nightly-2026-10-18-1df370f")
expect Pins.stable_tag("# `roc-stable` is fetched below\n") == Err(NoStableCompiler)
expect Pins.stable_tag("Fetch(\"roc-stable\", Recipes.roc_nightly(\"\"))") == Err(NoStableCompiler)
expect Pins.is_app(script) and Pins.is_app("app [main!] {}\n")
expect !Pins.is_app("Pins := [].{\n\tapp = 1\n}\n") and !Pins.is_app("package [A] {}\n")
expect Pins.roc_pin(script) == Ok("nightly-2026-10-18-1df370f")
expect Pins.roc_pin(example) == Err(NoPin)
expect Pins.roc_pin("app [main!] { heroc: \"nightly-1\" }\n") == Err(NoPin)
expect Pins.roc_pin("app [main!] { roc: \"a\", roc: \"b\" }\n") == Err(NoPin)
expect Pins.platform_of(example) == Ok("../../platform/main.roc")
expect Pins.platform_of(script) == Err(NoPlatform)
expect Pins.platform_of("app [config] { pf: platform \"https://example.com/p.tar.zst\" }\n") == Ok("https://example.com/p.tar.zst")
