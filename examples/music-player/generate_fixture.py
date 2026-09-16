#!/usr/bin/env python3
"""Generate the 200-track scaling fixture; codecs stay owned by Rodio/Symphonia.

This library is a stress test, not a demonstration: 200 short tones exist so the
scanner and the virtual list can be measured against a queue no one would hand
build. The library a person is meant to see is `library/`, which holds real
recordings and is tracked in Git, including the one file that cannot be decoded.
"""
from pathlib import Path
import math, struct, wave

root = Path(__file__).with_name("fixture")
root.mkdir(exist_ok=True)
for old in root.glob("*.wav"):
    old.unlink()
for ordinal in range(200):
    frequency = 220 + ordinal % 24 * 10
    with wave.open(str(root / f"track-{ordinal + 1:03}.wav"), "wb") as out:
        out.setparams((1, 2, 8_000, 0, "NONE", "not compressed"))
        samples = [int(math.sin(2 * math.pi * frequency * frame / 8_000) * 5_000) for frame in range(32_000)]
        out.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))
