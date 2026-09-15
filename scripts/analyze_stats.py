#!/usr/bin/env python3
"""Validate and summarize one Roc GUI .rgstats capture read-only."""

from __future__ import annotations

import argparse
import sqlite3
import statistics
import sys
from pathlib import Path


QUERY_DIR = Path(__file__).resolve().parent / "stats_queries"
VIEWS = (
    "semantic_health",
    "roc_work",
    "host_gpui_work",
    "virtual_list_materialization",
    "process_resources",
    "capture_health",
    "scaling",
    "spec_results",
)


def open_readonly(path: Path) -> sqlite3.Connection:
    database = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    database.execute("PRAGMA query_only=ON")
    database.execute("PRAGMA trusted_schema=OFF")
    return database


def validate(database: sqlite3.Connection) -> dict[str, str]:
    metadata = dict(database.execute("SELECT key,value FROM metadata"))
    if metadata.get("schema_version") != "6":
        raise RuntimeError("unsupported schema version")
    if metadata.get("clean_shutdown") != "1" or metadata.get("final_state") != "complete":
        raise RuntimeError("capture did not finalize cleanly")
    health = database.execute(
        "SELECT omitted_events,writer_failed,output_limited FROM recorder_health WHERE id=1"
    ).fetchone()
    if health is None or any(health):
        raise RuntimeError(f"capture evidence is incomplete: health={health!r}")
    return metadata


def summary(path: Path) -> str:
    with open_readonly(path) as database:
        metadata = validate(database)
        durations = [
            row[0]
            for row in database.execute(
                "SELECT c.duration_ns FROM cycles c JOIN runs r ON r.id=c.run_id "
                "WHERE c.measurement_phase='measured' AND r.phase='sample'"
            )
        ]
        runs = database.execute("SELECT count(*) FROM runs").fetchone()[0]
        steps = database.execute("SELECT count(*) FROM steps").fetchone()[0]
        cycles = database.execute("SELECT count(*) FROM cycles").fetchone()[0]
        return "\n".join(
            [
                f"Roc GUI capture: {path}",
                f"evidence_status=complete evidence_reason=capture finalized without recorded loss",
                f"spec={metadata.get('spec_name')!r} hash={metadata.get('spec_hash')} scale={metadata.get('benchmark_scale')}",
                f"backend={metadata.get('backend')} profile={metadata.get('target_profile')} host={metadata.get('host_os')}/{metadata.get('host_arch')}",
                f"runs={runs} steps={steps} cycles={cycles}",
                (
                    "marked operation: "
                    f"samples={len(durations)} min={min(durations) / 1e6:.3f}ms "
                    f"median={statistics.median(durations) / 1e6:.3f}ms "
                    f"spread={(max(durations) - min(durations)) / 1e6:.3f}ms"
                    if durations
                    else "marked operation: no measured samples"
                ),
                "Timing is report-only; semantic and evidence failures are the gates.",
            ]
        )


def compare(before: Path, after: Path) -> str:
    with open_readonly(before) as database:
        validate(database)
        after_uri = after.resolve().as_uri() + "?mode=ro"
        database.execute("ATTACH DATABASE ? AS after", (after_uri,))
        query = (Path(__file__).resolve().parent / "stats_queries" / "compare.sql").read_text(encoding="utf-8")
        row = database.execute(query).fetchone()
        if row is None:
            raise RuntimeError("comparison query returned no evidence")
        (status, reason, before_samples, before_min, before_median, before_spread,
         after_samples, after_min, after_median, after_spread, delta, ratio) = row
        if status != "complete":
            return f"evidence_status={status} evidence_reason={reason}"
        return "\n".join(
            [
                f"evidence_status={status} evidence_reason={reason}",
                f"before samples={before_samples} min={before_min / 1e6:.3f}ms median={before_median / 1e6:.3f}ms spread={before_spread / 1e6:.3f}ms",
                f"after samples={after_samples} min={after_min / 1e6:.3f}ms median={after_median / 1e6:.3f}ms spread={after_spread / 1e6:.3f}ms",
                f"median_delta={delta / 1e6:+.3f}ms median_ratio={ratio:.3f}",
                "Timing is report-only; semantic and evidence failures are the gates.",
            ]
        )


AA_COMPATIBILITY_KEYS = (
    "spec_hash", "benchmark_scale", "benchmark_samples", "benchmark_iterations",
    "benchmark_initial_size", "benchmark_change_size", "backend", "target_profile",
    "host_os", "host_arch", "cpu_model", "logical_cpu_count", "requested_detail",
    "job_count", "buffer_mib",
)


def perspective(path: Path, view: str, aa_bound: Path | None = None) -> str:
    query_path = QUERY_DIR / f"{view}.sql"
    query = query_path.read_text(encoding="utf-8")
    with open_readonly(path) as database:
        # Validate the capture before a view can label its evidence complete.
        # Views then retain their own per-family status and unavailable reasons.
        metadata = dict(database.execute("SELECT key,value FROM metadata"))
        if metadata.get("schema_version") != "6":
            raise RuntimeError("unsupported schema version")
        aa_sql = "SELECT NULL AS trigger, NULL AS spread_ns WHERE 0"
        if aa_bound is not None:
            with open_readonly(aa_bound) as aa_database:
                validate(aa_database)
            aa_uri = aa_bound.resolve().as_uri() + "?mode=ro"
            database.execute("ATTACH DATABASE ? AS aa", (aa_uri,))
            aa_metadata = dict(database.execute("SELECT key,value FROM aa.metadata"))
            if any(metadata.get(key) != aa_metadata.get(key) for key in AA_COMPATIBILITY_KEYS):
                raise RuntimeError("A/A bound capture is not mechanically comparable")
            aa_sql = (
                "SELECT cycles.trigger, max(cycles.duration_ns)-min(cycles.duration_ns) spread_ns "
                "FROM aa.cycles JOIN aa.runs ON aa.runs.id=cycles.run_id "
                "WHERE cycles.measurement_phase='measured' AND aa.runs.phase='sample' "
                "GROUP BY cycles.trigger"
            )
        query = query.replace("/* AA_BOUND */", aa_sql)
        cursor = database.execute(query)
        columns = [description[0] for description in cursor.description]
        rows = cursor.fetchall()
    output = [f"view={view} capture={path}", "\t".join(columns)]
    output.extend(
        "\t".join("NULL" if value is None else str(value) for value in row)
        for row in rows
    )
    return "\n".join(output)


def scaling_compare(base: Path, scaled: Path) -> str:
    query = (QUERY_DIR / "scaling_compare.sql").read_text(encoding="utf-8")
    with open_readonly(base) as database:
        validate(database)
        with open_readonly(scaled) as scaled_database:
            validate(scaled_database)
        database.execute("ATTACH DATABASE ? AS scaled", (scaled.resolve().as_uri() + "?mode=ro",))
        cursor = database.execute(query)
        columns = [description[0] for description in cursor.description]
        rows = cursor.fetchall()
    output = [f"view=scaling_compare base={base} scaled={scaled}", "\t".join(columns)]
    output.extend("\t".join("NULL" if value is None else str(value) for value in row) for row in rows)
    output.append("Timing is report-only; semantic and evidence failures are the gates.")
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--compare", type=Path, help="compare CAPTURE with this after capture")
    parser.add_argument("--view", choices=VIEWS, help="run a focused, read-only SQLite perspective")
    parser.add_argument("--aa-bound", type=Path,
                        help="validated unchanged-executable capture supplying the scaling A/A spread bound")
    parser.add_argument("--scale-against", type=Path,
                        help="report independent component ratios against a mechanically compatible larger-scale capture")
    args = parser.parse_args()
    if args.compare and args.view:
        parser.error("--compare and --view are mutually exclusive")
    if args.aa_bound and args.view != "scaling":
        parser.error("--aa-bound requires --view scaling")
    if args.scale_against and args.view != "scaling":
        parser.error("--scale-against requires --view scaling")
    if args.scale_against and args.aa_bound:
        parser.error("--scale-against and --aa-bound are mutually exclusive")
    try:
        if args.compare:
            result = compare(args.capture, args.compare)
        elif args.scale_against:
            result = scaling_compare(args.capture, args.scale_against)
        elif args.view:
            result = perspective(args.capture, args.view, args.aa_bound)
        else:
            result = summary(args.capture)
        print(result)
    except (OSError, sqlite3.Error, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
