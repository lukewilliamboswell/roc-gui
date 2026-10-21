import pf.Config
import pf.Url

import "freetype.json" as descriptor : Str

## The upstream descriptor is the sole reviewed source URL/checksum authority.
FreeType :: [].{
	Source : { url : Str, sha256 : Str }
	Descriptor : { source : Source }

	settings : List(Config.Setting)
	settings = {
		input : Descriptor
		input = Json.parse(descriptor) ?? crash "Invalid FreeType source descriptor"
		url = Url.from_quote(input.source.url) ?? crash "Invalid FreeType source URL"
		[
			Packages("freetype-pkgs", From(NixPackages("github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc"))),
			Executor("freetype-native", "nix", "freetype-pkgs"),
			SourceFile("freetype-source", url, input.source.sha256),
			Environment(
				"freetype-producer",
				[
					Tools([
						"freetype-pkgs#python3",
						"freetype-pkgs#bash",
						"freetype-pkgs#coreutils",
						"freetype-pkgs#cmake",
						"freetype-pkgs#gnumake",
						"freetype-pkgs#pkg-config",
						"freetype-pkgs#patchelf",
						"freetype-pkgs#binutils",
						"freetype-pkgs#glibc",
						"freetype-pkgs#glibc.dev",
						"freetype-pkgs#zlib",
						"freetype-pkgs#zlib.dev",
						"freetype-pkgs#bzip2",
						"freetype-pkgs#bzip2.dev",
						"freetype-pkgs#libpng",
						"freetype-pkgs#libpng.dev",
						"freetype-pkgs#harfbuzz",
						"freetype-pkgs#harfbuzz.dev",
						"freetype-pkgs#brotli",
						"freetype-pkgs#brotli.dev",
					]),
					Command("zig", "freetype-pkgs#zig_0_16"),
				],
			),
			Build(
				"freetype",
				[
					Execute("freetype-native"),
					Use("freetype-producer"),
					Files([
						"dependencies/FreeType.roc",
						"dependencies/freetype.json",
						"dependencies/linux/zig-toolchain.cmake",
						"scripts/build_freetype.py",
						"scripts/blueprint_link_inputs.py",
						"scripts/dependency_archive.py",
						"scripts/dependency_artifacts.py",
						"test/dependencies/freetype.c",
					]),
					Inputs(["freetype-source"]),
					Run(["python3", "scripts/build_freetype.py", "--inside", "--output", "dist"]),
					Output("dist"),
				],
			),
		]
	}
}
