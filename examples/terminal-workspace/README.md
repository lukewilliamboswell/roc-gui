# Terminal Workspace

A terminal workspace whose process access is an explicit host grant. It uses a
real pseudo-terminal, bounded asynchronous I/O through `Action.task`, searchable
virtualized scrollback, and stale-completion protection.

## Core capabilities

- Host-granted local-shell and deterministic-test profiles without an ambient executable API.
- Opaque typed grants and PTYs, bounded I/O, child exit, and cancellation.
- Virtualized line scrollback and incremental search through semantic controls.
- Generation-based reconciliation so stale worker completions cannot revive stopped sessions.

## Happy paths

- Start the granted profile, send text, and observe ordered PTY output.
- Search scrollback without changing the running child.
- Generate a realistic body of output with the ordinary `lines:N` fixture command.
- Stop a live child while a read is waiting and receive a cancellation completion.

## Appearance

An instrument panel: a charcoal ground, regions divided by hairline borders and
a one-point seam, 12-point body type over 18-point scrollback rows, a two-point
radius, and two status colours — amber for a session that is attached, red for
one that was refused or failed. `Theme.roc` holds every colour and measure the
application uses.

The command bar and the filter are not peers. The command bar sends text to a
child; the filter only narrows what is already on screen, so it sits as the
header of the well it filters.

An empty well is never a black rectangle. It carries a placard naming what the
state is and what would change it: nothing attached, attaching, waiting for
output, a session that ended, a filter that matches nothing, or a refusal that
names the exact `--host-cap-process` grant the workspace was launched without.

## Error paths

- Missing process grants are actionable.
- Invalid sizes, oversized I/O, concurrent reads, stale handles, invalid UTF-8, and child exits have typed outcomes.
- A stopped application generation ignores a late read completion.

## High-level goals

- Stress incremental rendering and the complete text-input/task-completion path.
- Establish a reusable explicit process-capability and PTY lifecycle pattern.
- SCM specs exercise a deterministic child through the real PTY and cover input, output, search, denial, stale completion, and cancellation.
- A scaling case produces long, varied scrollback through an ordinary terminal command.
