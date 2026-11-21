#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	roc: "nightly-2026-11-10-f7d1f19",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Pins

## Package the complete production semantic inventory for the shared runner.
## A built application describes the SCM files; this script never parses SCM.
Manifest : { schema_version : U64, compiler : Str, bundle : { name : Str } }

Description : { path : Str, runner : Str }

main! = |raw_args| {
	(version, manifest_path, output, describer) = match raw_args.map(OsStr.display) {
		[a, b, c, d] => (a, b, c, d)
		_ => return fail!("usage: blueprint run release-suite -- VERSION MANIFEST OUTPUT DESCRIBER")
	}
	manifest : Manifest
	manifest = Json.parse(Path.read_utf8!(Path.utf8(manifest_path))?) ?? return fail!("invalid release manifest")
	if manifest.schema_version != 3 or manifest.compiler == "" {
		return fail!("unsupported release manifest")
	}
	url = "https://github.com/lukewilliamboswell/roc-gui/releases/download/${version}/${manifest.bundle.name}"
	tracked = Cmd.new("git").args(["ls-files", "-z", "--", "examples", "benchmarks"]).capture!()?.split_on("\u(0)").keep_if(|path| path != "")
	roots = tracked.keep_if(|path| path.ends_with("/main.roc"))
	var $files = []
	for source in tracked {
		text = if source.ends_with("/main.roc") {
			original = Path.read_utf8!(Path.utf8(source))?
			dependency = Pins.platform_of(original) ?? return fail!("application has no unambiguous platform: ${source}")
			original.replace_each("platform \"${dependency}\"", "platform \"${url}\"")
		} else ""
		destination = if (source.starts_with("benchmarks/")) "examples/${source}" else source
		$files = $files.append({ source, destination, replacement: if (source.ends_with("/main.roc")) Ok(text) else Err(Missing) })
		# Fixture grants retain their repository-relative names.
		if source.starts_with("benchmarks/") {
			$files = $files.append({ source, destination: source, replacement: if (source.ends_with("/main.roc")) Ok(text) else Err(Missing) })
		}
	}
	var $apps = []
	for source in roots {
		parent = source.drop_suffix("/main.roc")
		specs = tracked.keep_if(|path| path.starts_with("${parent}/specs/") and path.ends_with(".scm"))
		if specs.is_empty() {
			return fail!("no specifications beside ${source}")
		}
		described = Cmd.new(OsStr.from_str(describer)).args(["--host-describe-specs"].concat(specs).map(OsStr.from_str)).capture!()?
		var $cases = []
		var $seen = []
		for line in described.split_on("\n").keep_if(|value| value.trim() != "") {
			record : Description
			record = Json.parse(line) ?? return fail!("invalid host specification description")
			if !specs.contains(record.path) or $seen.contains(record.path) {
				return fail!("duplicate or unexpected host description")
			}
			$seen = $seen.append(record.path)
			if record.runner == "semantic" {
				name = record.path.drop_prefix("${parent}/specs/").drop_suffix(".scm")
				$cases = $cases.append({ name, args: [source, record.path], stdin: "", stdout: "PASS semantic specification\n", stderr: "", exit_code: 0.I32 })
			} else if record.runner != "window" {
				return fail!("unknown host runner")
			}
		}
		if $seen.len() != specs.len() or $cases.is_empty() {
			return fail!("incomplete semantic inventory for ${source}")
		}
		$apps = $apps.append({ path: if (source.starts_with("benchmarks/")) "examples/${source}" else source, run: ["python3", "{suite}/scripts/archived_semantic.py", "{executable}"], cases: $cases })
	}
	plan = { version, url, files: $files, spec: { schema_version: 1.U64, release: version, dependencies: [url], apps: $apps } }
	Path.create_all!(Path.utf8(output))?
	plan_path = "${output}/suite-plan.json"
	Path.write_utf8!(Path.utf8(plan_path), Json.to_str(plan))?
	Cmd.new("python3").args(["scripts/suite_archive.py", OsStr.from_str(plan_path), OsStr.from_str(output)]).call!()
}

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
