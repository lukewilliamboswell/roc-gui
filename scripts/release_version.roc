#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-11-01-48d3369",
}
import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import src/ReleaseVersion

main! = |_| {
	event = Env.var_str!("EVENT")?
	var $version = Env.var_str!("REQUESTED") ?? ""
	if event == "workflow_dispatch" {
		if Env.var_str!("REF")? != Env.var_str!("DEFAULT_REF")? {
			return fail!("release from the default branch only")
		}
	} else {
		var $latest = []
		for entry in Path.list!("docs/releases")? {
			name = Path.filename(entry)?.display().drop_suffix(".adoc")
			match ReleaseVersion.parse(name) {
				Ok(parsed) => {
					$latest = $latest.append({ name, parsed })
				}
				Err(_) => {}
			}
		}
		ordered = $latest.sort_with(|a, b| ReleaseVersion.compare(a.parsed, b.parsed))
		$version = (ordered.last() ?? return fail!("no release notes found")).name
	}
	parsed = ReleaseVersion.parse($version) ?? return fail!("version must be SemVer without a v prefix or build metadata")
	if !(Path.is_file!(Path.utf8("docs/releases/${$version}.adoc"))?) {
		return fail!("write release notes first")
	}
	if event == "workflow_dispatch" {
		repository = Env.var_str!("GITHUB_REPOSITORY")?
		result = Cmd.new("gh").args(["api", OsStr.from_str("repos/${repository}/git/ref/tags/${$version}")]).run!()?
		if result.status == Exited(0) {
			return fail!("release tag already exists")
		}
		if !Str.from_utf8_lossy(result.stderr_bytes).contains("HTTP 404") {
			return fail!("could not establish whether the release tag exists")
		}
	}
	output = Env.var_str!("GITHUB_OUTPUT")?
	Path.append_utf8!(Path.utf8(output), "version=${$version}\nprerelease=${if (parsed.suffix == "") "false" else "true"}\n")
}

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
