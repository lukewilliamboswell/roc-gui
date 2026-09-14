#!/usr/bin/env python3
"""Regenerate the checked-in Roc host bindings."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("roc_source", type=Path, help="path to a Roc source checkout")
    args = parser.parse_args()
    glue_spec = args.roc_source.resolve() / "src/glue/src/RustGlue.roc"
    if not glue_spec.is_file():
        parser.error(f"Rust glue spec not found: {glue_spec}")

    subprocess.run(
        ["roc", "glue", str(glue_spec), "crates/host/src/", "platform/main-glue.roc"],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(["cargo", "fmt", "--all"], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
