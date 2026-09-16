# System Monitor

A read-only instrument panel for an explicitly granted view of CPU, memory,
disk I/O, network I/O, and processes.

Sampling is owned by the host's `sysinfo` integration and runs with timer waits
through the production task route. Overall CPU is normalized across the whole
machine and represented in tenths of one percent from 0 to 1000. Per-process
CPU uses the same unit and may exceed 1000 for multi-core use. Memory and I/O
values are bytes reported by the operating-system sampler, and are presented in
binary multiples named as such.

## What the design is for

An instrument is read at a glance and then read again a second later, so the
layout is built around one rule: a figure that changes must never move anything
around it. Every reading is a fixed-height tile, the status strip is a fixed
height whatever it says, the state pill has a floor on its width, the plot is a
fixed surface, and every number in the window is set in the fixed-pitch face so
its digits do not change width as they change value. The process table is made
of padded columns for the same reason: an `action_button` renders a caption
string rather than a child tree, so its columns are made the way a terminal
makes them.

Colour is spent on one thing. A single accent means *live* -- sampling is
running, this row is selected, this sort is in force -- and two warm colours
mean a bounded resource has crossed sixty and eighty percent. Four hues for
four metrics would have been decoration, and would have left a threshold
nothing distinctive to say.

## Explicitly unavailable, explicitly absent

Every metric is structurally either `Value` or `Unavailable`, and unavailable is
never displayed as a measured zero. A reading the operating system will not
report is recessed below its neighbours, shows a dash where the figure would
be, and carries a sentence naming the one sensor that is missing -- "Disk I/O
is not reported" rather than a shared "unavailable" that would suggest four
things are wrong when one is. In the history plot such a sample is drawn as a
stub at the baseline, because a bar of height zero would be a claim the sampler
never made.

## Authority

Nothing is read from the machine until a person presses Start, and holding a
grant is not the same as using it. A refusal is a designed state rather than an
error string: it says what happened, that nothing was read and nothing is held,
and what to press next. Pausing closes both the sampler and its timer and says
so, and warns that the figures still on screen are the last sample rather than
current values.

The process table exposes PID, display name, CPU, and memory only -- never
usernames, paths, command lines, environment, hostnames, or machine
identifiers.

## Specifications

Specifications use a deterministic host sampler through the identical snapshot
ABI and application state machine. They cover first run before anything has
been read, permission denial and a retry after it, unavailable sensors,
pause/resume, a superseded session, filtering and selection, bounded
newest-first history, host-owned counters, and a natural 500-process scaling
case through the ordinary table. `window-instrument.scm` opens the production
window and photographs the instrument idle, live, and paused, and asserts that
the status strip and the readings keep their heights across all three.
