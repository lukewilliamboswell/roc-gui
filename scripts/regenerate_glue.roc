#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	roc: "nightly-2026-11-10-f7d1f19",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout

## Regenerate the committed host bindings with the latest nightly.
##
##     blueprint run regenerate-glue -- <roc source>
##
## `<roc source>` is the source of the nightly that bare `roc` is, such as the
## nightly release's source archive unpacked. Its Rust glue specification
## describes the host interface that nightly expects; CI regenerates the
## bindings the same way and requires the committed files to match.
main! = |args| {
	source = match args.map(OsStr.display) {
		[only] => only
		_ => return fail!("usage: regenerate_glue.roc <roc source>")
	}
	spec = "${source}/src/glue/src/RustGlue.roc"
	if !Path.is_file!(Path.unix(spec))? {
		return fail!("no Rust glue specification at ${spec}")
	}
	run!("roc", ["glue", spec, "crates/host/src/", "platform/main-glue.roc"])?
	run!("cargo", ["fmt", "--all"])
}

run! : Str, List(Str) => Try({}, _)
run! = |program, args| {
	Stdout.line!("+ ${program} ${Str.join_with(args, " ")}")?
	Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).call!()
}

fail! = |message| {
	Stderr.line!("error: ${message}")?
	Err(Exit(1))
}
