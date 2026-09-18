#!/usr/bin/env python3
"""Run the native GPUI smoke check with a hard deadline."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--failure-record", type=Path)
    args = parser.parse_args()
    started = time.monotonic()
    print(f"START native-gpui-smoke utc={datetime.now(timezone.utc).isoformat(timespec='seconds')}", flush=True)
    try:
        status = subprocess.run(
            [str(args.executable.resolve()), "--host-gpui-smoke"],
            check=False,
            timeout=args.timeout,
        ).returncode
    except subprocess.TimeoutExpired:
        print(f"FAIL: GPUI smoke exceeded {args.timeout} seconds")
        status = 1
        outcome = "timeout"
    else:
        outcome = "pass" if status == 0 else "process_exit"
    elapsed = time.monotonic() - started
    print(
        f"END native-gpui-smoke outcome={outcome} elapsed={elapsed:.3f}s "
        f"utc={datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        flush=True,
    )
    if status != 0 and args.failure_record is not None:
        args.failure_record.parent.mkdir(parents=True, exist_ok=True)
        args.failure_record.write_text(json.dumps({
            "schema_version": 1,
            "case": "native-gpui-smoke",
            "outcome": outcome,
            "elapsed_seconds": round(elapsed, 3),
            "exit_status": f"0x{status & 0xFFFFFFFF:08X}",
        }, indent=2) + "\n", encoding="utf-8")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
