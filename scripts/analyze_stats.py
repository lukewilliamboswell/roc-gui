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
    if metadata.get("schema_version") != "2":
        raise RuntimeError("unsupported schema version")
    if metadata.get("clean_shutdown") != "1" or metadata.get("final_state") != "complete":
        raise RuntimeError("capture did not finalize cleanly")
    health = database.execute(
        "SELECT omitted_events,writer_failed,output_limited FROM recorder_health WHERE id=1"
    ).fetchone()
    if health is None or any(health):
        raise RuntimeError(f"capture evidence is incomplete: health={health!r}")
    return metadata


def percentile(values: list[int], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int((len(ordered) - 1) * fraction))
    return float(ordered[index])


def summary(path: Path) -> str:
    with open_readonly(path) as database:
        metadata = validate(database)
        durations = [
            row[0]
            for row in database.execute(
                "SELECT duration_ns FROM steps s JOIN runs r ON r.id=s.run_id "
                "WHERE s.role='operation' AND s.status='pass' AND r.phase='sample'"
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
                    f"samples={len(durations)} median={statistics.median(durations) / 1e6:.3f}ms "
                    f"p95={percentile(durations, .95) / 1e6:.3f}ms"
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
        status, reason, old, new, delta, ratio = row
        if status != "complete":
            return f"evidence_status={status} evidence_reason={reason}"
        return "\n".join(
            [
                f"evidence_status={status} evidence_reason={reason}",
                f"before_mean={old / 1e6:.3f}ms after_mean={new / 1e6:.3f}ms delta={delta / 1e6:+.3f}ms ratio={ratio:.3f}",
                "Timing is report-only; semantic and evidence failures are the gates.",
            ]
        )


def perspective(path: Path, view: str) -> str:
    query_path = QUERY_DIR / f"{view}.sql"
    query = query_path.read_text(encoding="utf-8")
    with open_readonly(path) as database:
        # Validate the capture before a view can label its evidence complete.
        # Views then retain their own per-family status and unavailable reasons.
        metadata = dict(database.execute("SELECT key,value FROM metadata"))
        if metadata.get("schema_version") != "2":
            raise RuntimeError("unsupported schema version")
        cursor = database.execute(query)
        columns = [description[0] for description in cursor.description]
        rows = cursor.fetchall()
    output = [f"view={view} capture={path}", "\t".join(columns)]
    output.extend(
        "\t".join("NULL" if value is None else str(value) for value in row)
        for row in rows
    )
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--compare", type=Path, help="compare CAPTURE with this after capture")
    parser.add_argument("--view", choices=VIEWS, help="run a focused, read-only SQLite perspective")
    args = parser.parse_args()
    if args.compare and args.view:
        parser.error("--compare and --view are mutually exclusive")
    try:
        if args.compare:
            result = compare(args.capture, args.compare)
        elif args.view:
            result = perspective(args.capture, args.view)
        else:
            result = summary(args.capture)
        print(result)
    except (OSError, sqlite3.Error, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
