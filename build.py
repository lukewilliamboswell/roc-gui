#!/usr/bin/env python3
"""Build the Roc GUI host archive."""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def output(*command: str) -> str:
    result = subprocess.run(command, cwd=ROOT, check=False, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def main() -> None:
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit("This initial platform supports Linux x86_64 only.")

    environment = os.environ.copy()
    environment["ROC_GUI_HOST_COMMIT"] = output("git", "rev-parse", "HEAD") or "unavailable"
    environment["ROC_GUI_HOST_DIRTY"] = "1" if output("git", "status", "--porcelain") else "0"
    subprocess.run(
        ["cargo", "build", "--release", "--package", "roc-gui-host"],
        cwd=ROOT,
        env=environment,
        check=True,
    )

    destination = ROOT / "platform/targets/x64glibc/libhost.a"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "target/release/libhost.a", destination)
    print(f"Built {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
