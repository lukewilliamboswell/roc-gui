#!/usr/bin/env python3
"""Build Roc GUI examples and run each .scm as one SQLite-backed app case."""

from __future__ import annotations

import argparse
import concurrent.futures
import atexit
import fnmatch
import os
import shutil
import sqlite3
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import replace
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUPPORTED_SCHEMA = 5


@dataclass(frozen=True)
class Case:
    spec: Path
    app: Path
    executable: Path
    capture: Path


def discover(patterns: list[str], output: Path) -> list[Case]:
    specs = sorted(
        [*ROOT.glob("examples/*/specs/*.scm"), *ROOT.glob("benchmarks/*/specs/*.scm")]
    )
    if patterns:
        specs = [
            spec
            for spec in specs
            if any(fnmatch.fnmatch(spec.relative_to(ROOT).as_posix(), pattern) for pattern in patterns)
        ]
    cases = []
    for spec in specs:
        app = spec.parent.parent / "main.roc"
        if not app.is_file():
            raise SystemExit(f"spec has no adjacent example main.roc: {spec}")
        slug = app.parent.name
        cases.append(
            Case(
                spec=spec,
                app=app,
                executable=output / "bin" / slug,
                capture=output / spec.relative_to(ROOT).with_suffix(".rgstats"),
            )
        )
    return cases


def build(cases: list[Case], roc: str, skip_host_build: bool) -> None:
    if not skip_host_build:
        subprocess.run(["python3", str(ROOT / "build.py")], cwd=ROOT, check=True)
    by_app = {case.app: case.executable for case in cases}
    for app, executable in sorted(by_app.items()):
        executable.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [roc, "build", f"--output={executable}", str(app)],
            cwd=ROOT,
            check=True,
        )


def validate_capture(path: Path) -> None:
    uri = path.resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(uri, uri=True) as database:
        database.execute("PRAGMA query_only=ON")
        database.execute("PRAGMA trusted_schema=OFF")
        metadata = dict(database.execute("SELECT key,value FROM metadata"))
        if int(metadata.get("schema_version", "-1")) != SUPPORTED_SCHEMA:
            raise RuntimeError("unsupported or missing schema version")
        if metadata.get("clean_shutdown") != "1" or metadata.get("final_state") != "complete":
            raise RuntimeError("capture did not finalize cleanly")
        if metadata.get("application_outcome") != "success":
            raise RuntimeError("application outcome is not success")
        bad_status = list(
            database.execute(
                "SELECT name,status,reason FROM measurement_status "
                "WHERE status='unfinalized' OR (status='partial' AND name<>'timing_environment') ORDER BY name"
            )
        )
        if bad_status:
            raise RuntimeError(f"incomplete evidence: {bad_status!r}")
        failed_runs = database.execute("SELECT count(*) FROM runs WHERE outcome<>'pass'").fetchone()[0]
        if failed_runs:
            raise RuntimeError(f"capture contains {failed_runs} failed run(s)")
        foreign_keys = list(database.execute("PRAGMA foreign_key_check"))
        if foreign_keys:
            raise RuntimeError(f"capture contains foreign-key violations: {foreign_keys!r}")


def run_case(case: Case, timeout: float, jobs: int, detail: str = "summary") -> tuple[Case, str | None]:
    case.capture.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(case.executable),
        "--host-run-spec",
        str(case.spec),
        f"--host-stats-output={case.capture}",
        f"--host-stats-job-count={jobs}",
        f"--host-stats-detail={detail}",
    ]
    fixture = case.app.parent / "fixture"
    if fixture.is_dir():
        command.extend(["--host-cap-dir", str(fixture)])
    if (case.app.parent / "fixture_server.py").is_file():
        command.extend(["--host-cap-http-origin", "http://127.0.0.1:38191"])
    app_data_fixture = case.app.parent / "app-data-fixture"
    clipboard_fixture = case.app.parent / "clipboard-fixture" / case.spec.stem
    if case.app.parent.name == "redis-explorer":
        command.extend(["--host-cap-tcp", "127.0.0.1:36379"])
    with tempfile.TemporaryDirectory(prefix="roc-gui-app-data-") as temporary:
        storage = Path(temporary)
        if app_data_fixture.is_dir():
            case_fixture = app_data_fixture / case.spec.stem
            default_fixture = app_data_fixture / "default"
            source = (
                case_fixture
                if case_fixture.is_dir()
                else default_fixture
                if default_fixture.is_dir()
                else app_data_fixture
            )
            shutil.copytree(source, storage, dirs_exist_ok=True)
            command.extend(["--host-cap-app-data", str(storage)])
        if clipboard_fixture.is_dir():
            command.append(f"--host-cap-clipboard-fixture={clipboard_fixture}")
        try:
            completed = subprocess.run(
                command,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return case, f"timed out after {timeout:g}s"
    if completed.returncode != 0:
        diagnostic = completed.stderr.decode(errors="replace").strip()
        return case, f"exit {completed.returncode}: {diagnostic}"
    try:
        validate_capture(case.capture)
    except (OSError, sqlite3.Error, RuntimeError, ValueError) as error:
        return case, f"invalid capture: {error}"
    return case, None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patterns", nargs="*", help="glob(s) matched against repository-relative spec paths")
    parser.add_argument("--jobs", type=int, default=1,
                        help="concurrent cases (default: 1; values above 1 make timing evidence partial)")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--detail", choices=("summary", "full"), default="summary",
                        help="omit setup cycles (summary) or record them too (full)")
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--aa", action="store_true",
                        help="repeat each passing case with the same executable for an A/A noise capture")
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=1)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--skip-host-build", action="store_true")
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    args = parser.parse_args()
    if args.jobs < 1 or args.timeout <= 0:
        parser.error("jobs and timeout must be positive")
    if args.shard_count < 1 or not 0 <= args.shard_index < args.shard_count:
        parser.error("shard index must be within shard count")
    return args


def main() -> int:
    args = parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or ROOT / ".test-out" / "specs" / stamp).resolve()
    cases = discover(args.patterns, output)
    cases = [case for index, case in enumerate(cases) if index % args.shard_count == args.shard_index]
    if not cases:
        print("error: no .scm specs selected", file=sys.stderr)
        return 2
    try:
        build(cases, args.roc, args.skip_host_build)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"error: build failed: {error}", file=sys.stderr)
        return 1

    fixture_processes: list[subprocess.Popen[bytes]] = []
    fixture_scripts = {case.app.parent / "fixture_server.py" for case in cases}
    fixture_scripts = {path for path in fixture_scripts if path.is_file()}
    fixture_ports = {"http-workbench": 38191, "redis-explorer": 36379}
    for script in sorted(fixture_scripts):
        fixture_process = subprocess.Popen(
            [sys.executable, str(script)], cwd=ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        fixture_processes.append(fixture_process)
        atexit.register(lambda process=fixture_process: process.poll() is None and process.terminate())
        port = fixture_ports.get(script.parent.name)
        if port is None:
            print(f"error: no readiness port declared for {script.parent.name}", file=sys.stderr)
            return 1
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                if fixture_process.poll() is not None:
                    print(f"error: local fixture failed to start: {script}", file=sys.stderr)
                    return 1
                time.sleep(0.02)
        else:
            fixture_process.terminate()
            print(f"error: local fixture did not become ready: {script}", file=sys.stderr)
            return 1

    results: list[tuple[Case, str | None]] = []
    if args.fail_fast:
        for case in cases:
            result = run_case(case, args.timeout, args.jobs, args.detail)
            results.append(result)
            if result[1] is not None:
                break
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(run_case, case, args.timeout, args.jobs, args.detail) for case in cases]
            results.extend(future.result() for future in concurrent.futures.as_completed(futures))

    failures = 0
    for case, error in results:
        relative = case.spec.relative_to(ROOT)
        if error is None:
            print(f"PASS {relative} -> {case.capture}")
        else:
            failures += 1
            print(f"FAIL {relative}: {error}", file=sys.stderr)
    if args.aa and failures == 0:
        for case, _ in sorted(results, key=lambda result: result[0].spec):
            aa_case = replace(
                case,
                capture=case.capture.with_name(f"{case.capture.stem}-aa{case.capture.suffix}"),
            )
            _, error = run_case(aa_case, args.timeout, 1, args.detail)
            if error is not None:
                failures += 1
                print(f"FAIL A/A {case.spec.relative_to(ROOT)}: {error}", file=sys.stderr)
            else:
                print(
                    f"A/A {case.spec.relative_to(ROOT)}: "
                    f"python3 scripts/analyze_stats.py {case.capture} --compare {aa_case.capture}"
                )
    passed = len(results) - failures
    print(f"{passed}/{len(cases)} specs passed; captures: {output}")
    for fixture_process in fixture_processes:
        fixture_process.terminate()
        fixture_process.wait(timeout=5)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
