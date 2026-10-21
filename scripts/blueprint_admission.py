"""Repository admission policy for Blueprint-produced FreeType artifacts.

Linux CI establishes exact build equivalence. Consumers check the reviewed
snapshot binding and artifact digest without preparing a provider recipe.
"""

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
import re

import blueprint_link_inputs

HEX256 = re.compile(r"[0-9a-f]{64}")
SNAPSHOT = re.compile(r"sha256:[0-9a-f]{64}")
DERIVATION = re.compile(r"/nix/store/[a-z0-9]{32}-[^/]+\.drv")
MAX_RECORD_BYTES = 16 * 1024 * 1024


class StaleAdmission(ValueError):
    """Reviewed binding does not match the current declared build snapshot."""


def validate_record(record):
    if (not isinstance(record, dict) or set(record) != {"schema_version", "provider", "build_identity", "snapshot_digest", "snapshot", "artifact"}
            or record.get("schema_version") != 1
            or record.get("provider") != "nix"
            or not DERIVATION.fullmatch(record.get("build_identity", ""))
            or not SNAPSHOT.fullmatch(record.get("snapshot_digest", ""))
            or not isinstance(record.get("snapshot"), dict)):
        raise ValueError("invalid Blueprint FreeType admission record")
    artifact = record.get("artifact", {})
    if (not isinstance(artifact, dict) or set(artifact) != {"name", "sha256", "size"}
            or artifact.get("name") != "freetype-x64glibc.tar"
            or not HEX256.fullmatch(artifact.get("sha256", ""))
            or type(artifact.get("size")) is not int or not 0 < artifact["size"] <= 2 * 1024**3):
        raise ValueError("invalid Blueprint FreeType admitted artifact")
    return record


def read_record(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_RECORD_BYTES:
        raise ValueError("missing or oversized Blueprint FreeType admission record")
    return validate_record(json.loads(path.read_text()))


def match_current(record, current, *, exact):
    """Distinguish exact recipe equivalence from a fresh admission binding."""
    validate_record(record)
    blueprint_link_inputs.validate_binding(current, 1)
    if exact:
        if current.get("prepared") is not True:
            raise ValueError("exact admission requires provider preparation")
        if (current["provider"], current["build_identity"]) != (
                record["provider"], record["build_identity"]):
            raise ValueError("FreeType build identity differs from the reviewed artifact")
    elif (current["snapshot_digest"] != record["snapshot_digest"]
          or current["snapshot"] != record["snapshot"]):
        raise StaleAdmission("FreeType admission is stale; Linux CI must compare the exact build identity")
    return dict(record, snapshot_digest=current["snapshot_digest"], snapshot=current["snapshot"])


def check_current(record, *, root=blueprint_link_inputs.ROOT):
    return match_current(record, blueprint_link_inputs.plan(root=root), exact=False)


def verify_bytes(archive, record):
    validate_record(record)
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size != record["artifact"]["size"]:
        raise ValueError("FreeType archive differs from admitted bytes")
    with archive.open("rb") as stream:
        measured = hashlib.file_digest(stream, "sha256").hexdigest()
    if measured != record["artifact"]["sha256"]:
        raise ValueError("FreeType archive differs from admitted digest")


def write_record(path, record):
    """Atomically refresh reviewed binding without exposing a partial sidecar."""
    validate_record(record)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        pending = Path(temporary.name)
    try:
        pending.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
        os.replace(pending, path)
    finally:
        pending.unlink(missing_ok=True)


def admit(archive, *, root=blueprint_link_inputs.ROOT, record_path=None):
    """Admit newly built or already reviewed bytes, without rebuilding them."""
    record = read_record(record_path or archive.with_suffix(archive.suffix + ".blueprint.json"))
    verify_bytes(archive, record)
    return match_current(record, blueprint_link_inputs.plan(prepare=True, root=root), exact=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--record", type=Path, help="Reviewed build sidecar; defaults to the archive's sidecar")
    parser.add_argument("--output", type=Path, required=True, help="New admission binding for this checkout")
    options = parser.parse_args()
    record = admit(options.archive.resolve(), record_path=options.record)
    # The caller owns committing or publishing this repository policy decision.
    write_record(options.output, record)


if __name__ == "__main__":
    main()
