app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.4.0-rc1/DWAeBdDr2vi43QDRpaq8t1C8UTvdyKUHR6aSaewNaKRx.tar.zst" }

import pf.Tool

import ".roc-version" as roc_version : Str

roc_tool = Tool.from_quote("rocpkgs.${roc_version.trim()}") ?? crash "Invalid .roc-version package name"

config = [
	Name("roc-gui"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Packages("default", From(NixPackages("github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc"))),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Tools([
				roc_tool,
				"rustup",
				"zig_0_16",
				"python3",
				"git",
				"pkg-config",
				"clang",
				"cmake",
				"gnumake",
				"curl",
				"zstd",
			]),
			ToolsFor("x86_64-linux", [
				"freetype",
				"fontconfig",
				"wayland",
				"libglvnd",
				"libxkbcommon",
				"alsa-lib",
				"vulkan-loader",
				"vulkan-headers",
			]),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),
	Task("build", [Use("dev"), Run(["python3", "build.py"])]),
	Task("test", [Use("dev"), Run(["python3", "scripts/run_specs.py", "--roc", "roc"])]),
	Task("lint", [Use("dev"), Run(["python3", "scripts/run_cargo.py", "clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps", "--", "-D", "warnings"])]),
	Task("check", [Use("dev"), Run(["python3", "scripts/toolchain.py", "--check", "--roc-bin", "roc"])]),
]
