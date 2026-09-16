# System Monitor

A read-only instrument panel for the local machine: CPU, memory, disk I/O, and
network I/O as fixed-height readings, a bar plot and a log of the last 120
samples, and a table of processes showing PID, name, CPU, and memory. The table
can be filtered by name, sorted by CPU or memory, and one row selected; the
selection follows its process across samples and says so when the process is
gone.

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

## Not yet built

- Read-only. Processes cannot be signalled, killed, or reniced.
- No per-core, per-disk, or per-interface breakdown; each metric is one machine-
  wide figure.
- History is 120 samples held in memory, with no persistence, export, or
  adjustable sampling interval.
- No alerting, thresholds beyond the two warm colours on bounded resources, or
  temperature, battery, and GPU sensors.

## Assets

The alert mark in `icons/` is vendored; its provenance and licence are in
`icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

Eleven specifications run on the semantic runner against a deterministic host
sampler reached through the same snapshot ABI as the real one, covering the
first frame before anything is read, refusal and retry, unavailable sensors,
pause and resume, a superseded session, filtering, sorting, a selection that
outlives its sample, bounded history, and a 500-process scaling case through the
ordinary table. One runs against the real window, photographing the instrument
idle, live, and paused and asserting that the status strip and readings keep
their heights across all three.
