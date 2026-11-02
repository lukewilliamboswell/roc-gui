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

## Orchestrate independent native productions and exact-byte comparisons.
main! = |raw_args| match raw_args.map(|arg| OsStr.from_raw(arg).display()) {
	["linux", first, second] => {
		sandbox!()?
		for name in ["alsa_interface", "freetype", "glibc", "unwind", "xkbcommon"] {
			native!("build_${name}", ["--output", first])?
			native!("build_${name}", ["--rebuild", "--output", second])?
		}
		compare_archives!(first, second)?
		native!("blueprint_admission", ["${first}/freetype-x64glibc.tar", "--output", "${first}/freetype-x64glibc.tar.blueprint.json"])?
		native!("check_linux_reproduction", [first])
	}
	["macos", first, second] => {
		native!("build_macos_interfaces", ["--output", first])?
		native!("build_macos_interfaces", ["--output", second])?
		compare_archives!(first, second)
	}
	["windows-cross", first, second, resource_first, resource_second, output] => {
		sandbox!()?
		native!("build_windows_gnu_runtime", ["--output", first])?
		native!("build_windows_gnu_runtime", ["--rebuild", "--output", second])?
		native!("build_windows_resource", ["--output", resource_first])?
		native!("build_windows_resource", ["--rebuild", "--output", resource_second])?
		native!("check_linux_reproduction", [first, "--target", "x64mingw"])?
		compare_archives!(first, second)?
		compare!("${resource_first}/roc-gui.res", "${resource_second}/roc-gui.res")?
		Path.create_all!(Path.utf8(output))?
		for entry in Path.list!(Path.utf8(first))? {
			name = Path.filename(entry)?.display()
			if name.ends_with(".tar") {
				Path.copy!(entry, Path.utf8("${output}/${name}"))?
			}
		}
		Path.copy!(Path.utf8("${resource_first}/roc-gui.res"), Path.utf8("${output}/roc-gui.res"))
	}
	["windows-native", first, second, resource_first, resource_second, candidate] => {
		for (runtime, resource) in [(first, resource_first), (second, resource_second)] {
			native!("build_windows_gnu_runtime", ["--output", runtime])?
			native!("build_windows_resource", ["--output", resource])?
		}
		compare_archives!(first, second)?
		compare!("${resource_first}/roc-gui.res", "${resource_second}/roc-gui.res")?
		compare!("${candidate}/roc-gui.res", "${resource_first}/roc-gui.res")
	}
	["probe-tag"] => {
		recipe : { probe_roc_version : Str }
		recipe = Json.parse(Path.read_utf8!("dependencies/windows-gnu-runtime.json")?) ?? return fail!("invalid runtime probe recipe")
		output = Env.var_str!("GITHUB_OUTPUT")?
		Path.append_utf8!(Path.utf8(output), "tag=${recipe.probe_roc_version}\n")
	}
	_ => fail!("usage: blueprint run link-inputs -- linux FIRST SECOND | macos FIRST SECOND | windows-cross FIRST SECOND RESOURCE_FIRST RESOURCE_SECOND OUTPUT | windows-native FIRST SECOND RESOURCE_FIRST RESOURCE_SECOND CANDIDATE | probe-tag")
}

sandbox! = || {
	setting = Cmd.new("nix").args(["config", "show", "sandbox"]).capture!()?.trim()
	if (setting == "true") Ok({}) else fail!("linker-input production requires the Nix sandbox")
}

native! = |name, args| Cmd.new("python3").args(["scripts/${name}.py"].concat(args).map(OsStr.from_str)).call!()

compare! = |first, second| Cmd.new("cmp").args([OsStr.from_str(first), OsStr.from_str(second)]).call!()

compare_archives! = |first, second| {
	var $compared = False
	for entry in Path.list!(Path.utf8(first))? {
		name = Path.filename(entry)?.display()
		if name.ends_with(".tar") {
			compare!("${first}/${name}", "${second}/${name}")?
			$compared = True
		}
	}
	if ($compared) Ok({}) else fail!("producer emitted no archives to compare")
}

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}
