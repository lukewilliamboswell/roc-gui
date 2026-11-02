#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-11-01-48d3369",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.System

## Generate the selected applications' production fixtures.
main! = |_| {
	separator = match System.target!().os() {
		Windows(_) => ";"
		_ => ":"
	}
	selected = Env.var_str!("ROC_GUI_SELECTED_APPS") ?? ""
	for name in ["database-browser", "music-player", "observatory"] {
		if selected == "" or selected.split_on(separator).contains("examples/${name}") {
			Cmd.new("python3").arg(OsStr.from_str("examples/${name}/generate_fixture.py")).call!()?
		}
	}
	Ok({})
}
