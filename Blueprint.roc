app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.4.0-rc1/DWAeBdDr2vi43QDRpaq8t1C8UTvdyKUHR6aSaewNaKRx.tar.zst" }

import pf.Tool
import dependencies/FreeType

import ".roc-version" as roc_version : Str

roc_tool = Tool.from_quote("default#rocpkgs.${roc_version.trim()}") ?? crash "Invalid .roc-version package name"

config = [
	Name("roc-gui"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Packages("default", From(NixPackages("github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc"))),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Resolver("nix", ["roc"]),
	Environment(
		"dev",
		[
			Tools([
				roc_tool,
				"default#rustup",
				"default#zig_0_16",
				"default#python3",
				"default#git",
				"default#pkg-config",
				"default#clang",
				"default#cmake",
				"default#gnumake",
				"default#curl",
				"default#zstd",
			]),
			ToolsFor(
				"x86_64-linux",
				[
					"default#freetype",
					"default#fontconfig",
					"default#wayland",
					"default#libglvnd",
					"default#libxkbcommon",
					"default#alsa-lib",
					"default#vulkan-loader",
					"default#vulkan-headers",
				],
			),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),
	Task("build", [Use("dev"), Run(["python3", "build.py"])]),
	Task("test", [Use("dev"), Run(["python3", "scripts/run_specs.py", "--roc", "roc"])]),
	Task("lint", [Use("dev"), Run(["python3", "scripts/run_cargo.py", "clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps", "--", "-D", "warnings"])]),
	Task("check", [Use("dev"), Run(["python3", "scripts/toolchain.py", "--check", "--roc-bin", "roc"])]),
].concat(FreeType.settings)
