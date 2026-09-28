#!/usr/bin/env python3
"""Run a command against a private headless Wayland compositor.

A Linux runner has no display. The host presents through GPUI's Wayland
client, so a real window needs a compositor. Sway's headless backend provides
one with a seat, which GPUI requires, and floats every window at the size it
asks for, as a desktop does. Windows render through whatever Vulkan device is
present; on a runner that is Mesa's software rasterizer.

Usage: headless_wayland.py -- COMMAND [ARGS...]
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

CONFIG = """\
output * resolution 1920x1080 scale 1
default_border none
for_window [all] floating enable
"""
STARTUP_SECONDS = 20


def main() -> int:
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    sway = shutil.which("sway")
    if sway is None:
        print("FAIL: sway is required to present a window without a display", file=sys.stderr)
        return 1
    # The socket path must fit in sockaddr_un, so the runtime directory is
    # short and private rather than under the caller's temporary directory.
    runtime = Path(tempfile.mkdtemp(prefix="rgwl-", dir="/tmp"))
    os.chmod(runtime, 0o700)
    config = runtime / "sway.conf"
    config.write_text(CONFIG)
    base = {key: value for key, value in os.environ.items() if key not in ("DISPLAY", "WAYLAND_DISPLAY")}
    base["XDG_RUNTIME_DIR"] = str(runtime)
    compositor = subprocess.Popen(
        [sway, "--config", str(config)],
        env={
            **base,
            "WLR_BACKENDS": "headless",
            "WLR_LIBINPUT_NO_DEVICES": "1",
            "WLR_RENDERER": "pixman",
        },
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + STARTUP_SECONDS
        socket = None
        while socket is None:
            if compositor.poll() is not None:
                print(f"FAIL: sway exited with {compositor.returncode} before listening", file=sys.stderr)
                return 1
            if time.monotonic() > deadline:
                print(f"FAIL: sway did not listen within {STARTUP_SECONDS}s", file=sys.stderr)
                return 1
            socket = next((path.name for path in runtime.glob("wayland-*") if path.is_socket()), None)
            if socket is None:
                time.sleep(0.05)
        return subprocess.run(command, env={**base, "WAYLAND_DISPLAY": socket}, check=False).returncode
    finally:
        compositor.terminate()
        try:
            compositor.wait(timeout=10)
        except subprocess.TimeoutExpired:
            compositor.kill()
        shutil.rmtree(runtime, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
