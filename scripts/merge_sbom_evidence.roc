#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-11-01-48d3369",
}
import cli.OsStr
import cli.Path
import cli.Stderr

Envelope : {
	format : Str,
	source : { server : Str, repository : Str, commit : Str },
	producer : { workflow : Str, run_id : Str, run_attempt : Str },
	generator : { tool : Str, tool_sha256 : Str, compiler : Str, generator : Str, blueprint : Str, created : Str },
	subjects : List({ name : Str, path : Str, size : U64, sha256 : Str, target : Str, version : Str, url : Str, inventory_sha256 : Str, sidecars : List({ name : Str, path : Str, size : U64, sha256 : Str, format : Str }) }),
	dependencies : List({ component : Str, origin : Str, state : Str, detail : Str }),
	coverage : List({ scope : Str, status : Str, detail : Str }),
}

## Combine same-run envelopes without altering their subjects or byte identities.
main! = |raw_args| {
	(output, inputs) = match raw_args.map(|arg| OsStr.from_raw(arg).display()) {
		[first, second, .. as rest] => (first, [second].concat(rest))
		_ => return fail!("usage: merge-sbom-evidence OUTPUT ENVELOPE...")
	}
	var $envelopes = []
	for path in inputs {
		parsed : Envelope
		parsed = Json.parse(Path.read_utf8!(Path.utf8(path))?) ?? return fail!("invalid SBOM evidence")
		$envelopes = $envelopes.append(parsed)
	}
	var $merged = $envelopes.first() ?? return fail!("no evidence supplied")
	var $names = []
	var $subjects = []
	var $dependencies = []
	var $coverage = []
	for envelope in $envelopes {
		if envelope.format != "roc-automation-sbom-evidence-v1" or envelope.source != $merged.source or envelope.producer != $merged.producer or envelope.generator != $merged.generator {
			return fail!("SBOM envelopes do not identify one producer, source and generator")
		}
		for subject in envelope.subjects {
			if $names.contains(subject.path) {
				return fail!("duplicate SBOM subject")
			}
			$names = $names.append(subject.path)
			$subjects = $subjects.append(subject)
		}
		$dependencies = $dependencies.concat(envelope.dependencies)
		$coverage = $coverage.concat(envelope.coverage)
	}
	$merged = { ..$merged, subjects: $subjects, dependencies: $dependencies, coverage: $coverage }
	Path.write_utf8!(Path.utf8(output), Json.to_str($merged))
}

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
