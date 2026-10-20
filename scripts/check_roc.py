#!/usr/bin/env python3
"""Check maintained Roc application roots with the pinned compiler; warnings fail."""

import argparse
import os
import subprocess

from toolchain import ROOT, validate_roots, verify_compiler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    args = parser.parse_args()
    verify_compiler(args.roc, validate_roots(ROOT))
    roots = [ROOT / "Blueprint.roc", *sorted([
        *ROOT.glob("examples/*/main.roc"), *ROOT.glob("benchmarks/*/main.roc")
    ])]
    failed = []
    for source in roots:
        relative = source.relative_to(ROOT)
        print(f"Checking {relative}", flush=True)
        result = subprocess.run([args.roc, "check", "--no-cache", str(relative)], cwd=ROOT)
        if result.returncode != 0:
            failed.append(relative)
    if failed:
        print("Roc errors or warnings: " + ", ".join(map(str, failed)), flush=True)
        return 1
    print(f"All {len(roots)} Roc roots checked without warnings.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
