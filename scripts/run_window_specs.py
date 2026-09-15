#!/usr/bin/env python3
"""Run .scm specifications against the real GPUI window, one process per case.

A sibling of run_specs.py rather than an extension of it. Window scenarios are
strictly serial: there is one screen, one focused application, and screenshots
of concurrent runs would photograph each other. Success is the JSON report, not
the SQLite capture, which a window run does not produce by default.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from run_specs import ROOT, build, fixture_metadata  # noqa: E402
from run_specs import Case as SemanticCase  # noqa: E402


@dataclass(frozen=True)
class WindowCase:
    spec: Path
    app: Path
    executable: Path
    output: Path

    @property
    def report(self) -> Path:
        return self.output / "report.json"


def discover(patterns: list[str], output: Path) -> list[WindowCase]:
    specs = sorted(ROOT.glob("examples/*/window-specs/*.scm"))
    if patterns:
        specs = [
            spec
            for spec in specs
            if any(
                fnmatch.fnmatch(spec.relative_to(ROOT).as_posix(), pattern)
                for pattern in patterns
            )
        ]
    cases = []
    for spec in specs:
        app = spec.parent.parent / "main.roc"
        if not app.is_file():
            raise SystemExit(f"window spec has no adjacent example main.roc: {spec}")
        slug = app.parent.name
        cases.append(
            WindowCase(
                spec=spec,
                app=app,
                executable=output / "bin" / slug,
                output=output / slug / spec.stem,
            )
        )
    return cases


def command(case: WindowCase, allow_missing_shots: bool) -> list[str]:
    arguments = [
        str(case.executable),
        "--host-run-window-spec",
        str(case.spec),
        f"--host-window-report={case.report}",
        f"--host-window-shot-dir={case.output}",
    ]
    if allow_missing_shots:
        arguments.append("--host-window-allow-missing-shots")
    fixtures = fixture_metadata(
        SemanticCase(
            spec=case.spec,
            app=case.app,
            executable=case.executable,
            capture=case.output,
        )
    )
    for key, value in sorted(fixtures.items()):
        if key == "directory":
            arguments += ["--host-cap-dir", str(case.app.parent / value)]
        elif key == "clipboard":
            arguments += [f"--host-cap-clipboard-fixture={case.app.parent / value}"]
        elif key == "http-origin":
            arguments += ["--host-cap-http-origin", value]
        elif key == "tcp":
            arguments += ["--host-cap-tcp", value]
    return arguments


def report_failure(case: WindowCase) -> None:
    """Print the failing step and any screenshots, so the next action is obvious."""
    try:
        report = json.loads(case.report.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        print(f"    no report written to {case.report}")
        return
    for step in report.get("steps", []):
        if step.get("status") in {"fail", "unavailable"}:
            print(f"    {step['status']}: {step.get('message', step.get('kind'))}")
    shots = sorted(case.output.glob("*.png"))
    for shot in shots:
        print(f"    screenshot: {shot}")


def run_case(case: WindowCase, timeout: int, allow_missing_shots: bool) -> bool:
    case.output.mkdir(parents=True, exist_ok=True)
    try:
        completed = subprocess.run(
            command(case, allow_missing_shots),
            cwd=ROOT,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"FAIL {case.spec.relative_to(ROOT)} (exceeded {timeout}s)")
        return False
    relative = case.spec.relative_to(ROOT)
    if completed.returncode == 0:
        print(f"PASS {relative} -> {case.report}")
        return True
    print(f"FAIL {relative} (exit {completed.returncode}) -> {case.report}")
    report_failure(case)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patterns", nargs="*", help="glob patterns over spec paths")
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--skip-host-build", action="store_true")
    parser.add_argument(
        "--allow-missing-shots",
        action="store_true",
        help="report unavailable screenshots instead of failing (CI runners "
        "cannot grant Screen Recording)",
    )
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = args.output_dir or ROOT / ".test-out" / "window" / stamp
    cases = discover(args.patterns, output)
    if not cases:
        print("no window specifications matched")
        return 1

    roc = "roc"
    build(
        [
            SemanticCase(
                spec=case.spec,
                app=case.app,
                executable=case.executable,
                capture=case.output,
            )
            for case in cases
        ],
        roc,
        args.skip_host_build,
    )

    passed = 0
    for case in cases:
        if run_case(case, args.timeout, args.allow_missing_shots):
            passed += 1
    print(f"{passed}/{len(cases)} window specs passed; reports: {output}")
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    raise SystemExit(main())
