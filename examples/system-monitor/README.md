# System Monitor

A live dashboard for CPU, memory, disk, network, and process activity, with
sampling performed by the production host integration that owns each metric.

## Core capabilities

- Periodic sampling with explicit unavailable values, sampling cadence, and pause/resume.
- Summary cards, time-series charts, sortable process tables, filtering, and process details.
- Stable selection while rows reorder and bounded history for charts.
- Platform capability detection and clear separation between observation and privileged actions.
- Export of the measurements actually recorded, with private machine identity omitted.

## Happy paths

- Observe live resource summaries, change the time range, pause and resume charts, and inspect a process.
- Sort and filter processes while preserving selection and open a resource-specific details panel.
- Change the sampling interval and export a bounded, privacy-safe observation session.
- Display unavailable platform metrics distinctly from measured zero values.

## Error paths

- Unsupported sensors, permission failures, exited processes, counter resets, and sampler failures remain distinguishable.
- Slow sampling cannot overlap indefinitely or relabel old readings with a new timestamp.
- Process actions require confirmation, handle races with process exit, and report the actual operating-system result.
- Export failure leaves the recorded session intact and offers a retry.

## High-level goals

- Drive charts, rapidly changing tables, stable identities, timers, and platform-owned measurement.
- Serve as the canonical example of honest unavailable data and privacy-safe reporting.
- SCM specs use a deterministic production sampler boundary and cover pause/resume, sorting, selection, unavailable values, and errors.
- A scaling case observes a naturally large process set without substituting a synthetic renderer.
