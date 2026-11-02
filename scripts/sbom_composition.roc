#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-11-01-48d3369",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr

Component : { kind : Str, copyright : Str, attribution : Str, package_url : Str, source_refs : List({ type : Str, url : Str }), id : Str, name : Str, producer : Str, version : Str, identity : Str, download : Str, sha256 : Str, license : Str, license_url : Str, modified : Str, target : Str, origin : Str }

Edge : { from : Str, to : Str, relation : Str, scope : Str, basis : Str }

Coverage : { scope : Str, component : Str, aspect : Str, status : Str, reason : Str, contact : Str }

Fragment : { components : List(Component), relationships : List(Edge), coverage : List(Coverage) }

Policy : { profile : Str, components : List(Component), relationships : List(Edge), coverage : List(Coverage), inputs : List({ input : Str, component : Str, reason : Str }), imported_documents : List(Str), unavailable_sboms : List(Str) }

Native : { bundle : Fragment, sources : List({ filename : Str, components : List(Component), relationships : List(Edge), coverage : List(Coverage) }) }

## Prepare per-deliverable compositions. Shared Blueprint tooling generates and
## independently checks the standard documents against each final file's bytes.
main! = |raw_args| {
	(version, directory, hosts, cache, output) = match raw_args.map(|arg| OsStr.from_raw(arg).display()) {
		[a, b, c, d, e] => (a, b, c, d, e)
		_ => return fail!("usage: blueprint run sbom-composition -- VERSION RELEASE HOSTS CACHE OUTPUT")
	}
	policy : Policy
	policy = Json.parse(Path.read_utf8!("sbom/composition.json")?) ?? return fail!("invalid reviewed SBOM policy")
	Path.create_all!(Path.utf8(output))?
	names = Path.list!(Path.utf8(directory))?.map_try(|entry| Path.filename(entry).map_ok(Path.display))?
	files = names.keep_if(|name| name.ends_with(".tar.zst") or name.ends_with(".tar") or name.ends_with(".zip") or name.ends_with(".pdf") or name == "release-manifest.json")
	var $native = empty_native
	if files.any(|name| name.ends_with(".tar.zst") or name.starts_with("gui-host-sources-")) {
		native_path = "${output}/native-inputs.json"
		Cmd.new("python3").args(["scripts/native_inventory.py", OsStr.from_str(directory), OsStr.from_str(hosts), OsStr.from_str(cache), OsStr.from_str(native_path)]).call!()?
		$native = Json.parse(Path.read_utf8!(Path.utf8(native_path))?) ?? return fail!("invalid native build inventory")
	}
	commit = Cmd.new("git").args(["rev-parse", "HEAD"]).capture!()?.trim()
	own = component("roc-gui", "roc-gui", version, "https://github.com/lukewilliamboswell/roc-gui/tree/${commit}", "UPL-1.0")
	compiler_version = Cmd.new("roc").arg("version").capture!()?.trim().drop_prefix("Roc compiler version ")
	compiler = component("roc-compiler", "Roc compiler", compiler_version, "https://github.com/roc-lang/nightlies/releases/tag/${compiler_version}", "UPL-1.0")
	renderer = component("roc-docs", "roc-docs renderer", "tools-0.9.0", "https://github.com/lukewilliamboswell/roc-automation/releases/tag/tools-0.9.0", "UPL-1.0")
	for filename in files {
		var $fragment = empty_fragment
		if filename.ends_with(".tar.zst") {
			$fragment = $native.bundle
		} else if filename.starts_with("gui-host-sources-") {
			selected = $native.sources.find_first(|source| source.filename == filename) ?? return fail!("source companion has no native inventory")
			$fragment = { components: selected.components, relationships: selected.relationships, coverage: selected.coverage }
		} else if filename.ends_with(".pdf") or filename.starts_with("roc-gui-docs-") {
			font_source = "https://github.com/lukewilliamboswell/roc-font/releases/download/0.1.0-rc4/3Es9Gca6KTySYDqcDPHwVqpAqJk6KwT9G4xkcLoYaSsx.tar.zst"
			fonts = ["Inter", "Merriweather", "FiraCode"].map(|name| component("font-${name}", name, "roc-font-0.1.0-rc4", "${font_source}#fonts/${name}", "OFL-1.1"))
			$fragment = { components: fonts.concat([renderer, component("roc-docs-theme", "roc-docs shared theme", "8afe656ea7de5586233683088eb6972b770f6832", "https://github.com/lukewilliamboswell/roc-automation/tree/8afe656ea7de5586233683088eb6972b770f6832/tools/roc-docs", "UPL-1.0")]), relationships: fonts.map(|font| edge("Subject", font.id, "contains", "", "Licensed font data embedded by the reviewed renderer")).concat([edge("Subject", renderer.id, "dependsOn", "build", "The renderer produced this document; its executable is not distributed in it"), edge("Subject", "roc-docs-theme", "contains", "", "Shared styling and presentation templates delivered in the rendered documentation")]), coverage: [gap("document-fonts", "The renderer embeds licensed font data/subsets. This inventory identifies the source font distribution, not a separately measured hash for each embedded subset.")] }
		} else if filename.starts_with("roc-gui-examples-") {
			# Native compilation is a later consumer operation; a source suite
			# depends on the bundle without containing its host binaries.
			dependency = component("released-platform", "roc-gui platform", version, "https://github.com/lukewilliamboswell/roc-gui/releases/tag/${version}", "UPL-1.0")
			recordings = component("music-recordings", "Public-domain piano excerpts", commit, "https://github.com/lukewilliamboswell/roc-gui/blob/${commit}/examples/music-player/library/NOTICE.md", "CC0-1.0")
			harness = component("python-runtime", "Python", "3", "https://www.python.org/downloads/", "PSF-2.0")
			$fragment = { components: [dependency, recordings, harness], relationships: [edge("Subject", dependency.id, "dependsOn", "runtime", "Archived application headers fetch the exact released platform bundle"), edge("Subject", recordings.id, "contains", "", "The retained NOTICE identifies the original CC0 recordings and transformations"), edge("Subject", harness.id, "dependsOn", "test", "External Python interpreter runs the independent semantic harness; no interpreter is archived")], coverage: [gap("examples-runtime", "Production captures and generated fixtures are included. Native dependency composition belongs to the separately bound platform SBOM; Python is an external test runtime.")] }
		}
		bound = { ..policy, components: $fragment.components.concat([own, compiler]), relationships: $fragment.relationships.concat([edge("Subject", own.id, "contains", "", "First-party code/documentation or release metadata in this deliverable"), edge("Subject", compiler.id, "dependsOn", "build", "Compiler used to produce/check the release, never claimed as shipped code")]), coverage: $fragment.coverage.append(gap("environment-closure", "The reviewed input dispositions distinguish development tools from delivered components. Native build-script/system-library closure remains explicitly bounded by retained production evidence.")) }
		Path.write_utf8!(Path.utf8("${output}/${filename}.composition.json"), Json.to_str(bound))?
	}
	Ok({})
}

component : Str, Str, Str, Str, Str -> Component
component = |id, name, version, identity, license| { id, name, version, identity, license, kind: "library", copyright: "NOASSERTION", attribution: "NOASSERTION", package_url: "", source_refs: [], producer: "NOASSERTION", download: "NOASSERTION", sha256: "", license_url: "", modified: "", target: "", origin: "reviewed" }

edge = |from, to, relation, scope, basis| { from, to, relation, scope, basis }

gap = |scope, reason| { scope, reason, component: "", aspect: "", status: "incomplete", contact: "https://github.com/lukewilliamboswell/roc-gui/issues" }

fail! = |message| {
	Stderr.line!(message)?
	Err(Exit(1))
}

empty_fragment : Fragment
empty_fragment = { components: [], relationships: [], coverage: [] }

empty_native : Native
empty_native = { bundle: empty_fragment, sources: [] }
