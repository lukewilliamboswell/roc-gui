# System Monitor

A read-only instrument panel for the local machine: CPU, memory, disk I/O, and
network I/O as fixed-height readings, a bar plot and a log of the last 120
samples, and a table of processes showing PID, name, CPU, and memory. The table
can be filtered by name, sorted by CPU or memory, and one row selected; the
selection follows its process across samples and says so when the process is
gone. The bar plot fills the width the window gives it: it hears that width
through the canvas's `on_size` and spreads a full history across it.

The example exercises a sampling session: two host resources, a `SystemMonitor`
sampler and a `Timer`, acquired together and closed together. Nothing is read
until Start is pressed, and each sample schedules the next wait on the ordinary
task route, so a generation counter retires a session that has been paused
rather than letting its late completion extend it. Every metric is structurally
either a value or unavailable, so a sensor the operating system will not report
shows a dash and a sentence naming it, never a measured zero.

The process table carries PID, display name, CPU, and memory only — no
usernames, paths, command lines, or machine identifiers.

## Running

```sh
python3 build.py
roc build --output=system-monitor examples/system-monitor/main.roc
./system-monitor -- --host-cap-system-monitor
```

The grant permits read-only local sampling. Without it, Start returns a refusal
that states nothing was read and nothing is held.

## Assets

The alert mark in `icons/` is vendored; its provenance and licence are in
`icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise sample lifetime, bounded history and scaling.
