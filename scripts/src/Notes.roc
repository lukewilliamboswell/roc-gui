## Release notes, from the authored AsciiDoc to the body of a GitHub release.
Notes := [].{

	## The notes with `{package-url}` set to the released bundle's URL, then the
	## compilers that built and tested the release. Notes that never name the
	## URL cannot tell a reader how to use the release.
	render : Str, { version : Str, bundle : Str, compilers : { roc : Str, roc_stable : Str } } -> Try(Str, [UnusedPlaceholder])
	render = |source, release| {
		if !source.contains("{package-url}") {
			return Err(UnusedPlaceholder)
		}
		url = "https://github.com/lukewilliamboswell/roc-gui/releases/download/${release.version}/${release.bundle}"
		body = markdown(Str.replace_each(source, "{package-url}", url).trim())
		Ok("${body}\n\n## Compilers\n\n```\n${release.compilers.roc}\n${release.compilers.roc_stable}\n```\n")
	}
}

# GitHub renders a release body as Markdown. The notes use only headings,
# paragraphs, lists and listing blocks, which differ from Markdown in their
# headings and their block delimiters alone.
markdown : Str -> Str
markdown = |adoc| {
	var $out = []
	var $language = ""
	for line in Str.split_on(adoc, "\n") {
		if line.starts_with("[source,") and line.ends_with("]") {
			$language = Str.drop_suffix(Str.drop_prefix(line, "[source,"), "]")
		} else if line == "----" {
			$out = $out.append("```${$language}")
			$language = ""
		} else if line.starts_with("== ") {
			$out = $out.append("## ${Str.drop_prefix(line, "== ")}")
		} else if line.starts_with("= ") {
			$out = $out.append("# ${Str.drop_prefix(line, "= ")}")
		} else {
			$out = $out.append(line)
		}
	}
	Str.join_with($out, "\n")
}

compilers : { roc : Str, roc_stable : Str }
compilers = { roc: "Roc compiler version nightly-2026-10-20-7a8a800", roc_stable: "Roc compiler version nightly-2026-10-18-1df370f" }

expect {
	source = "= roc-gui 0.1.0\n\nThe first release.\n\n== Use this release\n\n[source,roc]\n----\napp [State, main] { pf: platform \"{package-url}\" }\n----\n"
	notes = Notes.render(source, { version: "0.1.0", bundle: "abc.tar.zst", compilers })
	notes == Ok("# roc-gui 0.1.0\n\nThe first release.\n\n## Use this release\n\n```roc\napp [State, main] { pf: platform \"https://github.com/lukewilliamboswell/roc-gui/releases/download/0.1.0/abc.tar.zst\" }\n```\n\n## Compilers\n\n```\nRoc compiler version nightly-2026-10-20-7a8a800\nRoc compiler version nightly-2026-10-18-1df370f\n```\n")
}

expect Notes.render("= roc-gui 0.1.0\n", { version: "0.1.0", bundle: "abc.tar.zst", compilers }) == Err(UnusedPlaceholder)
