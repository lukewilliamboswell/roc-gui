# Development environment and tasks for roc-gui, realised by roc-blueprint.
#
#     blueprint run check    # the repository's Roc: pins, machine code, scripts, applications
#     blueprint run build    # the host and every application
#     blueprint run test     # the application specifications
#     blueprint run lint     # Clippy over the host
#     blueprint shell        # the development environment
#     blueprint update       # refresh Blueprint.lock
#
# `roc-stable` is the nightly named below; it runs the scripts under scripts/.
# Bare `roc` is the latest nightly, which the machine provides: the platform,
# its applications and its benchmarks name no compiler.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Recipes
import dependencies/FreeType

config = [
	Name("roc-gui"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Environment(
		"scripts",
		[
			Programs([Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-10-23-18478ff"))]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
				"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
			]),
			Expect(["roc", "git"]),
		],
	),
	# Regenerating the host bindings formats them with the repository's Rust
	# toolchain, which rustup selects from rust-toolchain.toml.
	Environment("glue", [Extend("scripts"), Expect(["cargo"])]),
	Environment(
		"dev",
		[
			Extend("scripts"),
			Tools([
				"nix#rustup",
				"nix#zig_0_16",
				"nix#python3",
				"nix#pre-commit",
				"nix#pkg-config",
				"nix#clang",
				"nix#cmake",
				"nix#gnumake",
				"nix#curl",
				"nix#zstd",
			]),
			ToolsFor(
				"x86_64-linux",
				[
					"nix#freetype",
					"nix#fontconfig",
					"nix#wayland",
					"nix#libglvnd",
					"nix#libxkbcommon",
					"nix#alsa-lib",
					"nix#vulkan-loader",
					"nix#vulkan-headers",
				],
			),
		],
	),
	Shell("default", [Use("dev")]),
	Task("check", [Use("scripts"), Run(["scripts/check_all.roc"])]),
	Task("build", [Use("dev"), Run(["python3", "build.py"])]),
	Task("test", [Use("dev"), Run(["python3", "scripts/run_specs.py", "--roc", "roc"])]),
	Task("lint", [Use("dev"), Run(["python3", "scripts/run_cargo.py", "clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps", "--", "-D", "warnings"])]),
	# Regenerate the committed host bindings: regenerate-glue -- <roc source>.
	Task("regenerate-glue", [Use("glue"), Run(["scripts/regenerate_glue.roc"])]),
	# Render a release's notes: release-notes -- <version> <bundle filename> <output>.
	Task("release-notes", [Use("scripts"), Run(["scripts/release_notes.roc"])]),
	# The tooling compiler, as release notes record it.
	Task("compiler-version", [Use("scripts"), Run(["roc-stable", "version"])]),
].concat(FreeType.settings)
