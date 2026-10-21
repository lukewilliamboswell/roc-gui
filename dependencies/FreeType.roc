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
			Packages("nix", From(NixPackages("github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc"))),
			Executor("freetype-native", "nix", "nix"),
			SourceFile("freetype-source", url, input.source.sha256),
			Environment(
				"freetype-producer",
				[
					Tools([
						"nix#python3",
						"nix#bash",
						"nix#coreutils",
						"nix#cmake",
						"nix#gnumake",
						"nix#pkg-config",
						"nix#patchelf",
						"nix#binutils",
						"nix#glibc",
						"nix#zlib",
						"nix#zlib.dev",
						"nix#bzip2.out",
						"nix#bzip2.dev",
						"nix#libpng",
						"nix#libpng.dev",
						"nix#harfbuzz",
						"nix#harfbuzz.dev",
						"nix#brotli.lib",
						"nix#brotli.dev",
					]),
					Command("zig", "nix#zig_0_16"),
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
