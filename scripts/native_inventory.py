#!/usr/bin/env python3
"""Read native archive/Cargo evidence for the Roc SBOM composition driver.

This format adapter does not generate SBOMs or choose release operations.
It reads exact-archive metadata already admitted by bundle_platform.py.
"""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

CONTACT = "https://github.com/lukewilliamboswell/roc-gui/issues"
SYSTEMS = {"x64glibc": "x86_64-linux", "arm64mac": "aarch64-darwin", "x64mingw": "x86_64-windows"}


def component(identifier, name, version, identity, download="NOASSERTION", sha256="", license="NOASSERTION", target="", kind="library", modified=""):
    return {"id": identifier, "name": name, "version": version, "identity": identity,
            "download": download, "sha256": sha256, "license": license, "target": target,
            "producer": "NOASSERTION", "license_url": "", "origin": "reviewed",
            "kind": kind, "copyright": "NOASSERTION", "attribution": "NOASSERTION",
            "package_url": identity if identity.startswith("pkg:") else "",
            "source_refs": [], "modified": modified}


def edge(source, destination, relation="dependsOn", scope="runtime", basis="Observed native build evidence"):
    return {"from": source, "to": destination, "relation": relation, "scope": scope, "basis": basis}


def gap(scope, reason):
    return {"scope": scope, "component": "", "aspect": "", "status": "incomplete", "reason": reason, "contact": CONTACT}


def archive_json(archive, member):
    with tarfile.open(archive) as packed:
        record = packed.getmember(member)
        if not record.isfile() or record.size > 32 * 1024**2:
            raise ValueError("invalid native inventory member")
        return json.load(packed.extractfile(record))


def checked_archive(directory, entry):
    path = directory / entry["asset"]
    if path.name != entry["asset"] or path.is_symlink() or path.stat().st_size != entry["size"]:
        raise ValueError("native archive differs from release manifest")
    with path.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != entry["sha256"]:
            raise ValueError("native archive digest differs from release manifest")
    return path


def cargo_graph(notice, metadata, host_id, target):
    packages = {p["id"]: p for p in notice["packages"]}
    identifiers = {key: f"{target}-crate-{index}" for index, key in enumerate(sorted(packages))}
    components, relationships = [], []
    for key, package in sorted(packages.items()):
        source = package["source"]
        source_refs, modified = [], ""
        if source.startswith("registry+"):
            identity = f"pkg:cargo/{package['name']}@{package['version']}"
            url = f"https://static.crates.io/crates/{package['name']}/{package['name']}-{package['version']}.crate"
            sha256 = package["crate_sha256"]
        else:
            git = package["git_source"]
            sha256 = git["archive_sha256"]
            identity = f"urn:roc-gui:cargo-source:{package['name']}:{package['version']}:sha256:{sha256}"
            url = git.get("archive_url", "NOASSERTION")
            source_refs = [{"type": "vcs", "url": source.removeprefix("git+")}]
            modified = f"Canonical Cargo source archive for {git['repository']}, revision {git['revision']}, path {git['path']}; digest identifies retained archive bytes."
        entry = component(identifiers[key], package["name"], package["version"], identity,
                          url, sha256, package["declared_license"] or "NOASSERTION", SYSTEMS[target], modified=modified)
        entry["source_refs"] = source_refs
        components.append(entry)
    metadata_packages = {p["id"]: p for p in metadata["packages"]}
    root = next(p["id"] for p in metadata["packages"] if p["name"] == "roc-gui-host" and p["source"] is None)
    selected = set(packages) | {root}
    connected = set()
    for node in metadata["resolve"]["nodes"]:
        if node["id"] not in selected:
            continue
        origin = host_id if node["id"] == root else identifiers[node["id"]]
        for dependency in node["deps"]:
            if dependency["pkg"] not in identifiers:
                continue
            kinds = {kind["kind"] for kind in dependency["dep_kinds"]}
            proc_macro = any("proc-macro" in t["kind"] for t in metadata_packages[dependency["pkg"]]["targets"])
            scope = "build" if proc_macro or None not in kinds else "runtime"
            relationships.append(edge(origin, identifiers[dependency["pkg"]], scope=scope,
                                      basis="Cargo resolved edge between packages observed in the sealed compilation"))
            connected.add(dependency["pkg"])
    # A package compiled solely as a build-script input remains build-only,
    # even when Cargo's target-filtered metadata omits its incoming edge.
    for key in set(identifiers) - connected:
        relationships.append(edge(host_id, identifiers[key], scope="build", basis="Sealed Cargo compilation set; no normal dependency edge established"))
    return components, relationships


def linker_source(name, original):
    """Use the source distribution selected by the recorded native recipe."""
    source = original.get("source", {})
    if name != "windows-gnu-runtime":
        return source, ""
    # The owning runtime producer emits 3 for native Windows and 4 for Linux.
    if original["schema_version"] not in (3, 4):
        raise ValueError("unsupported Windows runtime source evidence")
    source = source["native_toolchain" if original["schema_version"] == 3 else "toolchain"]
    if original["schema_version"] == 3 and original["build"]["toolchain_sha256"] != source["sha256"]:
        raise ValueError("Windows runtime source differs from its native builder")
    return source, "Download and SHA-256 identify the recorded Zig source distribution. Only selected runtime portions and corresponding sources are delivered; the compiler executable is not included."


def linker_component(target, archive_sha256, name, original, fingerprint):
    """Identify one code occurrence without aliasing its source distribution."""
    source, modified = linker_source(name, original)
    version = original.get("version", "sha256-" + original.get("catalog_sha256", fingerprint))
    source_url = source.get("url", "NOASSERTION")
    identity = f"urn:roc-gui:link-input:{target}:{archive_sha256}:{name}"
    result = component(target + "-native-" + name, name, version, identity, source_url,
                       source.get("sha256", ""), "UPL-1.0" if name in ("alsa", "macos-interfaces") else "NOASSERTION",
                       SYSTEMS[target], modified=modified)
    if source_url != "NOASSERTION":
        result["source_refs"] = [{"type": "source-distribution", "url": source_url}]
    return result


def inventory(release, hosts, cache):
    manifest = json.loads((release / "release-manifest.json").read_text())
    archives = manifest["hosts"]["archives"]
    platform_components, platform_edges, companions = [], [], []
    coverage = [gap("native-composition", "Cargo records the compiled dependency closure. Optimizer removal and native build-script/system-library composition are not proven by that record; retain source companions and runtime link evidence."),
                gap("supplier-sboms", "Native inputs retain exact source and archive identities; recursively bound supplier SBOMs are not available for every Cargo, system or generated-interface component.")]
    for target, system in SYSTEMS.items():
        host = checked_archive(hosts, archives["gui-host-" + target])
        source = checked_archive(hosts, archives["gui-host-sources-" + target])
        notice = archive_json(host, "licenses/gui-host/NOTICE.json")
        if notice["source_companion"]["sha256"] != archives["gui-host-sources-" + target]["sha256"]:
            raise ValueError("source companion differs from the sealed host notice")
        metadata = archive_json(source, "licenses/gui-host-sources/evidence/metadata.json")
        host_id = target + "-host"
        host_component = component(host_id, "roc-gui-host", manifest["hosts"]["source_fingerprint"],
                                   "urn:roc-gui:host:" + manifest["hosts"]["source_fingerprint"] + ":" + target,
                                   sha256=notice["host"]["sha256"], license="UPL-1.0", target=system)
        native, edges = cargo_graph(notice, metadata, host_id, target)
        platform_components += [host_component, *native]
        platform_edges += [edge("Subject", host_id, "contains", "", "Final platform bundle contains this exact sealed native host"), *edges]
        for name, tool in sorted(notice["toolchains"].items()):
            runtime_id = target + "-runtime-" + name
            platform_components.append(component(runtime_id, name + " runtime distribution", tool["version"],
                tool["source_url"], tool["source_url"], tool["archive_sha256"], target=system,
                modified="Source distribution identity; only linked runtime portions are used, not the compiler executable"))
            platform_edges.append(edge(host_id, runtime_id, basis="The native notice recipe retains the runtime distribution's source and terms"))
        companions.append({"filename": source.name, "components": native,
                           "relationships": [edge("Subject", c["id"], "contains", "", "Source companion retains the original compiled dependency source archives") for c in native],
                           "coverage": coverage})
    # Bind external archives separately from Cargo's dependency graph. Their
    # retained dependency.json files carry the component recipes and evidence.
    lock = manifest["external_inputs"]
    for target, record in lock["targets"].items():
        if target not in SYSTEMS:
            raise ValueError("unexpected linker-input target")
        identifier = target + "-link-inputs"
        entry = component(identifier, "roc-gui-link-inputs", lock["release"],
                          f"https://github.com/{lock['repository']}/releases/tag/{lock['release']}",
                          f"https://github.com/{lock['repository']}/releases/download/{lock['release']}/{record['asset']}",
                          record["sha256"], target=SYSTEMS[target])
        platform_components.append(entry)
        platform_edges.append(edge("Subject", identifier, "contains", "", "Final bundle contains the admitted linker inputs and corresponding sources"))
        archive = checked_archive(cache / "link-inputs", {**record, "asset": record["sha256"] + ".tar"})
        admitted = archive_json(archive, "dependency.json")
        if admitted["target"] != target or admitted["input_fingerprint"] != lock["source"]["input_fingerprint"]:
            raise ValueError("linker-input component metadata differs from the selected release")
        for name, original in sorted(admitted["components"].items()):
            child = linker_component(target, record["sha256"], name, original, admitted["input_fingerprint"])
            platform_components.append(child)
            platform_edges.append(edge(identifier, child["id"], "contains", "", "The admitted dependency.json records this component's exact source/recipe identity"))

    return {"bundle": {"components": platform_components, "relationships": platform_edges, "coverage": coverage}, "sources": companions}


if __name__ == "__main__":
    release, hosts, cache, output = map(Path, sys.argv[1:])
    output.write_text(json.dumps(inventory(release, hosts, cache), sort_keys=True) + "\n")
