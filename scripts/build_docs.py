#!/usr/bin/env python3
"""Build the manual and compiler API with the Blueprint-locked shared renderer."""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", action="store_true", help="accepted for compatibility; PDF is always built")
    parser.add_argument("--roc", default="roc", help="compiler that generates the API reference")
    parser.add_argument("--docs-version", default="unreleased", help="platform version this manual documents")
    args = parser.parse_args()
    output = Path(os.environ.get("DOCS_OUT", ".docs-out"))
    if output.is_absolute():
        try:
            output = output.relative_to(ROOT)
        except ValueError:
            parser.error("DOCS_OUT must be inside the repository; use a workspace-relative path")
    subprocess.run(
        [
            "blueprint", "run", "docs", "--",
            "--roc-command", args.roc,
            "--docs-version", args.docs_version,
            "--output-directory", output.as_posix(),
        ],
        cwd=ROOT,
        check=True,
    )


if __name__ == "__main__":
    main()
