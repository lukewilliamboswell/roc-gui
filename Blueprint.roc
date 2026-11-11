# Development environment and tasks for roc-gui, realised by roc-blueprint.
#
#     blueprint run check    # the repository's Roc: pins, machine code, scripts, applications
#     blueprint run build    # the host and every application
#     blueprint run test     # the application specifications
#     blueprint run lint     # Clippy over the host
#     blueprint run docs     # HTML, PDF, Markdown and compiler API reference
#     blueprint shell        # the development environment
#     blueprint update       # refresh Blueprint.lock
#
# `roc-stable` is the nightly named below; it runs the scripts under scripts/.
# Bare `roc` is the latest nightly, which the machine provides: the platform,
# its applications and its benchmarks name no compiler.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.13.0/DBtzmMfrSgt6nCGVAcZYCVPxWbhpqw3MXpm6sdQzMn4v.tar.zst" }

import pf.Recipes
import pf.Config
import pf.System
import dependencies/FreeType

docs_renderer : System -> Config.Download
docs_renderer = |system| match system {
	"x86_64-linux" | "aarch64-darwin" => File("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/roc-docs-${system.to_str()}")
	_ => Unavailable
}

release_package : System -> Config.Download
release_package = |system| File("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/release-package-${system.to_str()}")

script_runtime : List(Config.EnvironmentSetting)
script_runtime = [
	Programs([Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-11-10-f7d1f19"))]),
	# Every bundle the scripts depend on, including dependencies of
	# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
	RocPackages([
		"https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
		"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	]),
]

config = [
	Name("roc-gui"),
	Systems(["x86_64-linux", "aarch64-darwin", "x86_64-windows"]),
	Environment("scripts", script_runtime.concat([Expect(["roc", "git"])])),

	Environment("producer", script_runtime.concat([Expect(["git", "python3"])])),
	Environment("release-metadata", [Extend("producer"), Expect(["gh"])]),
	Environment("archive-test", [Programs([Fetch("release-package", release_package)]), Expect(["roc", "git", "unzip"])]),
	# Glue formatting uses the Rust toolchain selected by rustup.
	Environment("glue", [Extend("scripts"), Expect(["cargo"])]),
	# The renderer is a verified native download; API generation uses the
	# caller's compiler, independently of the tooling compiler above.
	Environment("docs", [Programs([Fetch("roc-docs", docs_renderer)]), Expect(["realpath", "sh"])]),
	Environment(
		"dev",
		[
			Extend("scripts"),
			ToolsFor(
				"x86_64-linux",
				[
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
			ToolsFor(
				"aarch64-darwin",
				[
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
				],
			),

		],
	),
	Shell("default", [Use("dev")]),
	Task("check", [Use("scripts"), Run(["scripts/check_all.roc"])]),
	Task("build", [Use("dev"), Run(["scripts/build.roc"])]),
	Task("test", [Use("dev"), Run(["python3", "scripts/run_specs.py", "--roc", "roc"])]),
	Task("lint", [Use("dev"), Run(["python3", "scripts/run_cargo.py", "clippy", "--locked", "--package", "roc-gui-host", "--all-targets", "--no-deps", "--", "-D", "warnings"])]),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-gui.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-gui/", "--api-entrypoint", "platform/main.roc"])]),
	Task("bootstrap", [Use("scripts"), Run(["scripts/bootstrap.roc"])]),
	Task("test-archive", [Use("archive-test"), Run(["release-package", "test-archive"])]),
	Task("link-inputs", [Use("producer"), Run(["scripts/link_inputs.roc"])]),
	Task("release-version", [Use("release-metadata"), Run(["scripts/release_version.roc"])]),
	Task("release-build", [Use("scripts"), Run(["scripts/release.roc"])]),
	Task("merge-sbom-evidence", [Use("scripts"), Run(["scripts/merge_sbom_evidence.roc"])]),
	Task("sbom-composition", [Use("scripts"), Run(["scripts/sbom_composition.roc"])]),
	Task("release-suite", [Use("scripts"), Run(["scripts/release_suite.roc"])]),
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	# Regenerate the committed host bindings: regenerate-glue -- <roc source>.
	Task("regenerate-glue", [Use("glue"), Run(["scripts/regenerate_glue.roc"])]),
	# Render a release's notes: release-notes -- <version> <bundle filename> <output>.
	Task("release-notes", [Use("scripts"), Run(["scripts/release_notes.roc"])]),
	# The tooling compiler, as release notes record it.
	Task("compiler-version", [Use("scripts"), Run(["roc-stable", "version"])]),
].concat(FreeType.settings)
