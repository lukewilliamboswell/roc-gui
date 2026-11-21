#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	roc: "nightly-2026-11-10-f7d1f19",
}

import cli.Cmd
import cli.OsStr
import cli.Stderr
import cli.Stdout
import cli.System

## Build the native host and stage the admitted linker inputs.
main! = |raw_args| {
	args = raw_args.map(OsStr.display)
	target = match (System.target!().os(), System.target!().arch()) {
		(Linux(_), X64) => "x64glibc"
		(MacOS(_), Arm64) => "arm64mac"
		(Windows(_), X64) => "x64mingw"
		_ => return fail!("unsupported native host")
	}
	var $flags = []
	var $candidate = []
	var $rest = args
	while !$rest.is_empty() {
		match $rest {
			[flag, .. as rest] if ["--debug", "--skip-inputs", "--source-inputs"].contains(flag) => {
				$flags = $flags.append(flag)
				$rest = rest
			}
			["--candidate-inputs", directory, .. as rest] => {
				$candidate = [directory]
				$rest = rest
			}
			_ => return fail!("usage: blueprint run build -- [--debug] [--skip-inputs] [--source-inputs] [--candidate-inputs DIRECTORY]")
		}
	}
	if !$candidate.is_empty() and (target != "x64glibc" or !$flags.contains("--skip-inputs")) {
		return fail!("--candidate-inputs requires --skip-inputs on Linux")
	}
	adapter = ["scripts/native_build.py"]
	if !$flags.contains("--source-inputs") and !$flags.contains("--skip-inputs") {
		run!("python3", adapter.concat(["validate", "--target", target]))?
	}
	if target == "x64mingw" {
		run!("python3", adapter.concat(["windows", "--target", target]).concat($flags))?
	} else {
		cargo = ["scripts/run_cargo.py", "build", "--locked", "--package", "roc-gui-host"]
		profile = if ($flags.contains("--debug")) [] else ["--release"]
		command = Cmd.new("python3").args(cargo.concat(profile).map(OsStr.from_str))
		selected = match $candidate {
			[directory] => command.env("ROC_GUI_CANDIDATE_ALSA", OsStr.from_str("${directory}/alsa-x64glibc.tar"))
			_ => command
		}
		sha = Cmd.new("git").args(["rev-parse", "HEAD"]).capture!()?.trim()
		dirty = Cmd.new("git").args(["status", "--porcelain"]).capture!()?.trim() != ""
		selected.env("ROC_GUI_HOST_COMMIT", OsStr.from_str(sha)).env("ROC_GUI_HOST_DIRTY", if (dirty) "1" else "0").call!()?
		run!("python3", adapter.concat(["stage", "--target", target]).concat($flags))?
	}
	Stdout.line!("Built platform/targets/${target}/libhost.a")
}

run! = |program, args| Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).call!()

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
