#!/usr/bin/env python3
"""Independent harness for one immutable published semantic SCM case.

Compilation belongs to the shared runner. The executable owns SCM parsing,
capability grants, event routing, assertions and capture measurements. This
adapter invokes the same run_case/fixture_services path as working-tree tests.
"""
from contextlib import redirect_stdout, redirect_stderr
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile

from run_specs import Case, describe, fixture_services, run_case

ROOT = Path(__file__).resolve().parents[1]


def member(name):
    path = ROOT / name
    if not path.resolve().is_relative_to(ROOT) or path.is_symlink():
        raise ValueError("unsafe fixture or specification path")
    return path


def materialize_fixtures():
    verified = set()
    for alias in json.loads((ROOT / "fixture-aliases.json").read_text()):
        source, destination = member(alias["source"]), member(alias["path"])
        identity = (str(source), alias["sha256"])
        if identity not in verified:
            if hashlib.sha256(source.read_bytes()).hexdigest() != alias["sha256"]:
                raise ValueError("fixture payload differs from the archived alias identity")
            verified.add(identity)
        if destination.exists():
            if not os.path.samefile(source, destination) and hashlib.sha256(destination.read_bytes()).hexdigest() != alias["sha256"]:
                raise ValueError("materialized fixture differs from the archive")
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(source, destination)
        except OSError:
            destination.write_bytes(source.read_bytes())


def execute(executable, application, specification):
    materialize_fixtures()
    app, spec = member(application), member(specification)
    if spec.parent.parent != app.parent or not spec.is_file():
        raise ValueError("specification must be beside its application")
    with tempfile.TemporaryDirectory(prefix="roc-gui-archived-semantic-") as temporary:
        output = Path(temporary)
        case = Case(spec, app, Path(executable).resolve(),
                    ROOT / "semantic-evidence" / spec.relative_to(ROOT).with_suffix(".rgstats"))
        described = describe([case])
        if described[spec]["runner"] != "semantic":
            raise ValueError("archived semantic case describes a different runner")
        with fixture_services([case], described, output / "fixtures"):
            _, error = run_case(case, described[spec], 290, 1)
            if error is not None:
                raise RuntimeError(error)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8", newline="\n")
    diagnostics = io.StringIO()
    try:
        with redirect_stdout(diagnostics), redirect_stderr(diagnostics):
            execute(*sys.argv[1:])
    except Exception as error:
        print(diagnostics.getvalue(), file=sys.stderr, end="")
        print(f"FAIL semantic specification: {error}", file=sys.stderr)
        raise SystemExit(1)
    print("PASS semantic specification")
