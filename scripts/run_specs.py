#!/usr/bin/env python3
"""Build Roc GUI examples and run each .scm as one SQLite-backed app case."""

from __future__ import annotations

import argparse
import concurrent.futures
import atexit
from contextlib import closing, contextmanager
import fnmatch
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from dataclasses import replace
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUPPORTED_SCHEMA = 10


@dataclass(frozen=True)
class Case:
    spec: Path
    app: Path
    executable: Path
    capture: Path


def describe(cases: list[Case]) -> dict[Path, dict]:
    """Ask the host what each specification needs.

    The host owns the `.scm` vocabulary, so it is the only parser: it reports
    the runner a case needs and the very capability flags its declared grants
    become. Duplicating that vocabulary here would be a second source of truth
    that could drift.
    """
    executable = next((case.executable for case in cases if case.executable.is_file()), None)
    if executable is None:
        raise RuntimeError("no built executable available to describe specifications")
    completed = subprocess.run(
        [str(executable), "--host-describe-specs", *[str(case.spec) for case in cases]],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        diagnostic = completed.stderr.decode(errors="replace").strip()
        raise RuntimeError(f"specification description failed: {diagnostic}")
    described: dict[Path, dict] = {}
    for line in completed.stdout.decode(errors="replace").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        described[Path(record["path"])] = record
    missing = [case.spec for case in cases if case.spec not in described]
    if missing:
        raise RuntimeError(f"host did not describe {len(missing)} specification(s)")
    return described


@contextmanager
def fixture_services(cases: list[Case], described: dict[Path, dict], output: Path):
    """Run the loopback services the selected cases declare."""
    output.mkdir(parents=True, exist_ok=True)
    processes: list[subprocess.Popen[bytes]] = []
    servers = set()
    for case in cases:
        for server in described[case.spec]["servers"]:
            servers.add((server["script"], int(server["port"])))
    try:
        for script, port in sorted(servers):
            ready_file = output / f"fixture-ready-{port}"
            environment = os.environ.copy()
            environment["ROC_GUI_FIXTURE_READY_FILE"] = str(ready_file)
            process = subprocess.Popen(
                [sys.executable, script], cwd=ROOT,
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                env=environment,
            )
            processes.append(process)
            atexit.register(lambda process=process: process.poll() is None and process.terminate())
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if ready_file.is_file():
                    break
                if process.poll() is not None:
                    diagnostic = process.stderr.read().decode(errors="replace").strip()
                    suffix = f": {diagnostic}" if diagnostic else ""
                    raise RuntimeError(f"local fixture failed to start{suffix}")
                time.sleep(0.02)
            else:
                process.terminate()
                process.wait(timeout=5)
                diagnostic = process.stderr.read().decode(errors="replace").strip()
                suffix = f": {diagnostic}" if diagnostic else ""
                raise RuntimeError(f"local fixture did not report readiness{suffix}")
        yield
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


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
    subprocess.run([sys.executable, str(ROOT / "scripts/bootstrap.py")], cwd=ROOT, check=True)
    if not skip_host_build:
        sys.path.insert(0, str(ROOT / "scripts"))
        from install_released_host import install
        if not install():
            subprocess.run([sys.executable, str(ROOT / "build.py")], cwd=ROOT, check=True)
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
    with closing(sqlite3.connect(uri, uri=True)) as database:
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


def report_window_failure(artifacts: Path) -> None:
    """Print the failing step and any screenshots, so the next look is one read away."""
    try:
        report = json.loads((artifacts / "report.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        print(f"    no report written to {artifacts / 'report.json'}", file=sys.stderr)
        return
    for step in report.get("steps", []):
        if step.get("status") in {"fail", "unavailable"}:
            print(f"    {step['status']}: {step.get('message', step.get('kind'))}", file=sys.stderr)
    for shot in sorted(artifacts.glob("*.png")):
        print(f"    screenshot: {shot}", file=sys.stderr)


def window_artifacts(case: Case) -> Path:
    """Where a window case writes its report and screenshots."""
    return case.capture.with_suffix("")


def run_case(
    case: Case,
    grants: dict,
    timeout: float,
    jobs: int,
    detail: str = "summary",
    runner: str = "semantic",
    allow_missing_shots: bool = False,
) -> tuple[Case, str | None]:
    """Run one specification on the runner its steps require.

    Both runners share this function so a case is wired to the capabilities its
    specification declares exactly once, whichever runner it needs.
    """
    case.capture.parent.mkdir(parents=True, exist_ok=True)
    if runner == "window":
        artifacts = window_artifacts(case)
        artifacts.mkdir(parents=True, exist_ok=True)
        command = [
            str(case.executable),
            "--host-run-window-spec",
            str(case.spec),
            f"--host-window-report={artifacts / 'report.json'}",
            f"--host-window-shot-dir={artifacts}",
        ]
        if allow_missing_shots:
            command.append("--host-window-allow-missing-shots")
    else:
        command = [
            str(case.executable),
            "--host-run-spec",
            str(case.spec),
            f"--host-stats-output={case.capture}",
            f"--host-stats-job-count={jobs}",
            f"--host-stats-detail={detail}",
        ]
    command.extend(grants["flags"])
    with tempfile.TemporaryDirectory(prefix="roc-gui-app-data-") as temporary:
        storage = Path(temporary)
        # Application data is granted as a fresh private copy, so a case writes
        # through the production capability without mutating checked-in data.
        if seed := grants["app_data_seed"]:
            shutil.copytree(seed, storage, dirs_exist_ok=True)
            command.extend(["--host-cap-app-data", str(storage)])
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
    if runner == "window":
        # A window run's evidence is its report, not a SQLite capture, which it
        # does not produce.
        report = window_artifacts(case) / "report.json"
        try:
            outcome = json.loads(report.read_text(encoding="utf-8")).get("outcome")
        except (OSError, json.JSONDecodeError) as error:
            return case, f"unreadable window report: {error}"
        if outcome != "pass":
            return case, f"window report outcome {outcome!r}"
        return case, None
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
    parser.add_argument("--only", choices=("all", "semantic", "window"), default="all",
                        help="run only the specifications a given runner handles")
    parser.add_argument("--allow-missing-shots", action="store_true",
                        help="report unavailable screenshots instead of failing; hosted CI "
                             "runners cannot grant screen recording")
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

    # Ask the host what each specification needs, before the loopback services
    # start, because the services a run needs come from the cases it will
    # actually execute.
    try:
        described = describe(cases)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    semantic = [case for case in cases if described[case.spec]["runner"] == "semantic"]
    window = [case for case in cases if described[case.spec]["runner"] == "window"]
    if args.only == "semantic":
        window = []
    elif args.only == "window":
        semantic = []
    if not semantic and not window:
        print(f"error: no .scm specs selected for --only {args.only}", file=sys.stderr)
        return 2
    selected = semantic + window

    results: list[tuple[Case, str | None]] = []
    failures = 0
    window_specs = {case.spec for case in window}
    try:
        with fixture_services(selected, described, output):
            if args.fail_fast:
                for case in semantic:
                    result = run_case(case, described[case.spec], args.timeout, args.jobs, args.detail)
                    results.append(result)
                    if result[1] is not None:
                        break
            else:
                with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
                    futures = [
                        pool.submit(run_case, case, described[case.spec], args.timeout, args.jobs, args.detail)
                        for case in semantic
                    ]
                    results.extend(future.result() for future in concurrent.futures.as_completed(futures))

            # Window cases are strictly serial: there is one screen and one
            # focused application, so concurrent runs would photograph each
            # other.
            for case in window:
                result = run_case(
                    case,
                    described[case.spec],
                    args.timeout,
                    1,
                    args.detail,
                    runner="window",
                    allow_missing_shots=args.allow_missing_shots,
                )
                results.append(result)
                if args.fail_fast and result[1] is not None:
                    break

            for case, error in results:
                relative = case.spec.relative_to(ROOT)
                evidence = (
                    window_artifacts(case) / "report.json"
                    if case.spec in window_specs
                    else case.capture
                )
                if error is None:
                    print(f"PASS {relative} -> {evidence}")
                else:
                    failures += 1
                    print(f"FAIL {relative}: {error}", file=sys.stderr)
                    if case.spec in window_specs:
                        report_window_failure(window_artifacts(case))
            # A/A repeats measure timing noise between two captures, which a
            # window run does not produce.
            if args.aa and failures == 0:
                for case, _ in sorted(
                    (result for result in results if result[0].spec not in window_specs),
                    key=lambda result: result[0].spec,
                ):
                    aa_case = replace(
                        case,
                        capture=case.capture.with_name(f"{case.capture.stem}-aa{case.capture.suffix}"),
                    )
                    _, error = run_case(aa_case, described[case.spec], args.timeout, 1, args.detail)
                    if error is not None:
                        failures += 1
                        print(f"FAIL A/A {case.spec.relative_to(ROOT)}: {error}", file=sys.stderr)
                    else:
                        print(
                            f"A/A {case.spec.relative_to(ROOT)}: "
                            f"python3 scripts/analyze_stats.py {case.capture} --compare {aa_case.capture}"
                        )
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    passed = len(results) - failures
    print(f"{passed}/{len(results)} specs passed; evidence: {output}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
