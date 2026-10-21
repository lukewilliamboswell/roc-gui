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
			Packages("default", From(NixPackages("github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc"))),
			Executor("freetype-native", "nix", "default"),
			SourceFile("freetype-source", url, input.source.sha256),
			Environment(
				"freetype-producer",
				[
					Tools([
						"default#python3",
						"default#bash",
						"default#coreutils",
						"default#cmake",
						"default#gnumake",
						"default#pkg-config",
						"default#patchelf",
						"default#binutils",
						"default#glibc",
						"default#glibc.dev",
						"default#zlib",
						"default#zlib.dev",
						"default#bzip2",
						"default#bzip2.dev",
						"default#libpng",
						"default#libpng.dev",
						"default#harfbuzz",
						"default#harfbuzz.dev",
						"default#brotli",
						"default#brotli.dev",
					]),
					Command("zig", "default#zig_0_16"),
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
