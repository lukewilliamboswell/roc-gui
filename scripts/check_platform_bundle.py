#!/usr/bin/env python3
"""Serve an exact platform bundle and exercise every maintained application."""

import argparse
import json
from functools import partial
import http.server
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import threading

from host_build_identity import TARGETS
from toolchain import replace_platform, pin_release_app, verify_compiler
from run_specs import Case, fixture_services, run_case

ROOT = Path(__file__).resolve().parents[1]


def check(directory: Path, roc: str) -> None:
    manifest = json.loads((directory / "release-manifest.json").read_text())
    if manifest["schema_version"] != 2:
        raise ValueError("unsupported release manifest")
    verify_compiler(roc, manifest["compiler"])
    bundles = [path for path in directory.iterdir() if path.name.endswith(".tar.zst")]
    if len(bundles) != 1:
        raise ValueError("release directory must contain exactly one platform bundle")
    target = TARGETS.get((platform.system(), platform.machine()))
    if target is None:
        raise ValueError("bundle validation requires a supported native runner")
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/bootstrap.py")],
        cwd=ROOT,
        check=True,
        env={**os.environ, "ROC": roc},
    )
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}/{bundles[0].name}"
    try:
        with tempfile.TemporaryDirectory(prefix="roc-gui-release-check-") as temporary:
            stage = Path(temporary)
            applications = sorted([*ROOT.glob("examples/*/main.roc"), *ROOT.glob("benchmarks/*/main.roc")])
            cases = []
            for source in applications:
                app = stage / source.parent.parent.name / source.parent.name
                shutil.copytree(source.parent, app)
                main = app / "main.roc"
                main.write_text(pin_release_app(replace_platform(main.read_text(), url), manifest["compiler"]))
                executable = stage / "bin" / source.parent.parent.name / source.parent.name
                executable.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run([roc, "build", "--opt=dev", "--no-cache", f"--target={target}",
                                f"--output={executable}", str(main)], check=True, timeout=180)
                for spec in sorted(app.glob("specs/*.scm")):
                    cases.append(Case(
                        spec=spec,
                        app=main,
                        executable=executable,
                        capture=stage / "captures" / source.parent.parent.name / source.parent.name / f"{spec.stem}.rgstats",
                    ))
                if source.parent.name == "counter" and platform.system() == "Darwin":
                    subprocess.run([str(executable), "--host-gpui-smoke"], check=True, timeout=30)
            with fixture_services(cases, stage / "fixtures"):
                for case in cases:
                    _, error = run_case(case, 180, 1)
                    if error is not None:
                        raise RuntimeError(f"{case.spec}: {error}")
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()
    check(args.directory.resolve(), args.roc)
