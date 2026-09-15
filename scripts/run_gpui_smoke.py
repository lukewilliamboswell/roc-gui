#!/usr/bin/env python3
"""Run the native GPUI smoke check with a hard deadline."""

import argparse
from pathlib import Path
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()
    try:
        return subprocess.run(
            [str(args.executable.resolve()), "--host-gpui-smoke"],
            check=False,
            timeout=args.timeout,
        ).returncode
    except subprocess.TimeoutExpired:
        print(f"FAIL: GPUI smoke exceeded {args.timeout} seconds")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
