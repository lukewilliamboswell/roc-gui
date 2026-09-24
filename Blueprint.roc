app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.3.0/DdfMePZbeL5hodg7j4B6Jzpm9t555B9SPPAJNQ5WzCR9.tar.zst" }

import pf.Tool

import ".roc-version" as roc_version : Str

roc_tool = Tool.from_quote("rocpkgs.${roc_version.trim()}") ?? crash "Invalid .roc-version package name"

config = [
	Name("roc-gui"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Overlay("github:roc-lang/roc-overlay"),
	Shell(
		"default",
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
				"freetype",
				"fontconfig",
				"wayland",
				"libglvnd",
				"libxkbcommon",
				"alsa-lib",
				"vulkan-loader",
				"vulkan-headers",
			]),
		],
	),
	Task("build", [Run(["python3", "build.py"])]),
	Task("test", [Run(["python3", "scripts/run_specs.py", "--roc", "roc"])]),
	Task("lint", [Run(["python3", "scripts/run_cargo.py", "clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps", "--", "-D", "warnings"])]),
	Task("check", [Run(["python3", "scripts/toolchain.py", "--check", "--roc-bin", "roc"])]),
]
