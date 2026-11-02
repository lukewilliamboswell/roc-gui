#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-11-01-48d3369",
}

import cli.Env
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr

## Build the final release once from sealed native hosts, then prepare the
## immutable semantic suite, documentation, notes and per-artifact SBOM inputs.
Manifest : { bundle : { name : Str } }

main! = |raw_args| {
	(version, output, hosts, cache) = match raw_args.map(|arg| OsStr.from_raw(arg).display()) {
		[a, b, c, d] => (a, b, c, d)
		_ => return fail!("usage: blueprint run release-build -- VERSION OUTPUT HOSTS CACHE")
	}
	if Cmd.new("git").args(["diff", "--quiet", "HEAD"]).run!()?.status != Exited(0) {
		return fail!("release assembly requires clean committed sources")
	}
	Cmd.new("python3").args(["scripts/verify_release_attestations.py", "link-inputs.lock.json", "--cache", OsStr.from_str(cache)]).call!()?
	run!("python3", ["scripts/bundle_platform.py", "--link-inputs", "link-inputs.lock.json", "--hosts", hosts, "--output", output, "--cache", cache])?
	run!("blueprint", ["run", "bootstrap"])?
	describer = "${cache}/suite-describer"
	run!("roc", ["build", "--no-cache", "--opt=dev", "--output=${describer}", "examples/counter/main.roc"])?
	run!("blueprint", ["run", "release-suite", "--", version, "${output}/release-manifest.json", output, describer])?
	run!("blueprint", ["run", "docs", "--", "--docs-version", version])?
	run!("python3", ["scripts/check_docs.py"])?
	run!("python3", ["scripts/document_archive.py", version, output])?
	manifest : Manifest
	manifest = Json.parse(Path.read_utf8!(Path.utf8("${output}/release-manifest.json"))?) ?? return fail!("release manifest is invalid")
	run!("blueprint", ["run", "release-notes", "--", version, manifest.bundle.name, "${cache}/release-notes.md"])?
	run!("blueprint", ["run", "sbom-composition", "--", version, output, hosts, cache, "${cache}/sbom-compositions"])?
	match Env.var_str!("GITHUB_OUTPUT") {
		Ok(path) => Path.append_utf8!(Path.utf8(path), "bundle=${manifest.bundle.name}\n")
		Err(_) => Ok({})
	}
}

run! = |program, args| Cmd.new(OsStr.from_str(program)).clear_envs().envs(Env.dict!().keep_if(|(name, _)| !["GH_TOKEN", "GITHUB_TOKEN"].contains(name.display()))).args(args.map(OsStr.from_str)).call!()

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
