#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-23-18478ff",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Notes

## Render a release's notes for the body of its GitHub release.
##
##     scripts/release_notes.roc <version> <bundle filename> <output>
##
## The notes are `docs/releases/<version>.adoc`, which the manual includes as
## written. `{package-url}` stands for the bundle's URL, which holds its content
## hash and so is known only once the release has built it. A "Compilers"
## section records the `roc` and `roc-stable` that built and tested the release.
main! = |args| {
	(version, bundle, output) = match args.map(|arg| OsStr.from_raw(arg).display()) {
		[a, b, c] => (a, b, c)
		_ => return fail!("usage: release_notes.roc <version> <bundle filename> <output>")
	}
	source = Path.read_utf8!(Path.unix("docs/releases/${version}.adoc"))?
	compilers = {
		roc: version_of!("roc")?,
		roc_stable: version_of!("roc-stable")?,
	}
	match Notes.render(source, { version, bundle, compilers }) {
		Ok(notes) => Path.write_utf8!(Path.unix(output), notes)
		Err(UnusedPlaceholder) => fail!("docs/releases/${version}.adoc never names {package-url}")
	}
}

version_of! : Str => Try(Str, _)
version_of! = |program| Ok(Cmd.new_str(program).args_str(["version"]).exec_output!()?.stdout_utf8.trim())

fail! = |message| {
	Stderr.line!("error: ${message}")?
	Err(Exit(1))
}
