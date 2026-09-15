#!/usr/bin/env python3
"""Generate small deterministic PCM WAV fixtures; codecs stay owned by Rodio/Symphonia."""
from pathlib import Path
import math, struct, wave

root = Path(__file__).with_name("fixture")
root.mkdir(exist_ok=True)
for old in root.glob("track-*.wav"):
    old.unlink()
for ordinal in range(200):
    frequency = 220 + ordinal % 24 * 10
    with wave.open(str(root / f"track-{ordinal + 1:03}.wav"), "wb") as out:
        out.setparams((1, 2, 8_000, 0, "NONE", "not compressed"))
        samples = [int(math.sin(2 * math.pi * frequency * frame / 8_000) * 5_000) for frame in range(32_000)]
        out.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))
(root / "broken.wav").write_bytes(b"not a media file")
