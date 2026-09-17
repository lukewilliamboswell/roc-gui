#!/usr/bin/env python3
"""Print a scaling matrix from a directory of SQLite observatory captures."""

from __future__ import annotations

import argparse
import sqlite3
import statistics
from pathlib import Path


def value(db: sqlite3.Connection, key: str) -> str:
    row = db.execute("SELECT value FROM metadata WHERE key=?", (key,)).fetchone()
    return row[0] if row else ""


def summarize(path: Path) -> tuple[object, ...] | None:
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        db.execute("PRAGMA query_only=ON")
        if value(db, "schema_version") != "16":
            raise RuntimeError(f"{path}: unsupported schema")
        if value(db, "clean_shutdown") != "1":
            raise RuntimeError(f"{path}: incomplete capture")
        if value(db, "benchmark_scale") in ("", "0"):
            return None
        cycles = db.execute(
            "SELECT c.roc_callback_ns,c.validate_ns,c.graph_apply_ns,c.gpui_apply_ns "
            "FROM cycles c JOIN runs r ON r.id=c.run_id "
            "WHERE r.phase='sample' AND c.measurement_phase='measured' ORDER BY c.id"
        ).fetchall()
        if not cycles:
            raise RuntimeError(f"{path}: no measured sample cycles")
        med = lambda values: int(statistics.median(values)) if values else None
        gpui = [row[3] for row in cycles if row[3] is not None]
        alloc = db.execute(
            "SELECT sum(end_roc_alloc_requested_bytes-start_roc_alloc_requested_bytes) "
            "FROM runs WHERE phase='sample'"
        ).fetchone()[0]
        return (
            value(db, "spec_name"),
            int(value(db, "benchmark_initial_size")),
            int(value(db, "benchmark_change_size")),
            int(value(db, "benchmark_scale")),
            len(cycles),
            med([row[0] for row in cycles]),
            med([row[1] for row in cycles]),
            med([row[2] for row in cycles]),
            med(gpui),
            alloc,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_dir", type=Path)
    args = parser.parse_args()
    captures = sorted(args.capture_dir.rglob("*.rgstats"))
    if not captures:
        parser.error("capture directory contains no .rgstats files")
    print("case\tinitial\tchanged\tscale\tsamples\troc_median_ns\tvalidate_median_ns\tgraph_apply_median_ns\tgpui_apply_median_ns\troc_allocated_across_samples_bytes")
    for capture in captures:
        try:
            row = summarize(capture)
        except (RuntimeError, sqlite3.Error, ValueError) as error:
            parser.error(str(error))
        if row is not None:
            print("\t".join("NULL" if item is None else str(item) for item in row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
