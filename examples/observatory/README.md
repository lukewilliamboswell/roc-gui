# Observatory

A read-only explorer for `.rgstats` captures, the SQLite databases the roc-gui
recorder writes for every specification, benchmark, and recorded session. It
opens one capture from a single-file grant, offering only `.rgstats` files, or
takes a directory grant, lists every capture in the folder with its identity and
a health badge, and opens one. Either way the capture is read through the
platform's ordinary SQLite capability. It queries the capture's tables itself and depends on no other
tool.

A capture of any schema other than 19 is refused with its reason before a single
table is read. An open capture always shows its identity and health first: a
bar of chips for backend, detail, schema, finalisation, shutdown, recording
gaps, and timing quality, and a banner on every view when the capture cannot be
trusted. Five views follow:

- **Overview**: identity from `metadata`, and tiles for outcome, slowest
  trigger, median cycle, frames over budget, skip rate, and verdict.
- **Interactions**: the triggers table, cycles grouped by trigger and patch kind
  within one measurement phase, with count, minimum, median, maximum, and
  interquartile range. Below it, the slowest cycles of the phase in a virtual
  list, each with a bar of callback, validate, apply, and unattributed time;
  choosing a trigger narrows the list to its cycles. Pressing a cycle opens the
  inspector: a waterfall of the cycle's time through the Roc callback and its
  five work spans, validate, and apply with graph and GPUI apply, where the time
  no owner attributed is shown as `unattributed` and a Σ check proves the parts
  sum to the cycle; the eleven component work kinds; graph and keyed work; and
  the allocations of each span. A cycle driven by a specification step opens
  the Spec view at that step. Warmup runs are excluded.
- **Spec**: the runs, a run selector, and the selected run's steps with their
  status, duration, and expected and observed values, in a virtual list.
- **Memory**: allocations by trigger and span (calls and bytes, mean, maximum,
  and total), each run's Roc allocation lifecycle, and each run's user and
  system CPU and peak and current RSS, with a bar of peak RSS per run.
- **Health**: the verdict and the rule that produced it, every measurement
  family, recording gaps, recorder health, every identity key, and the declared
  unavailable sources.

Every number belongs to a measurement family. A family whose status is not
`complete` is shown as `—` with its status and reason, never as zero, and
pressing a `—` opens Health at that family. Values the capture records per
cycle follow the same rule: spans and their allocations are `—` for a callback
whose spans were not valid, component work is `—` for a cycle with no component
observation (and an absent kind is zero only for one with it), GPUI apply is
`—` when it was not recorded, and a run with no end snapshot has no CPU, RSS,
or allocation change. The capture list and the triggers table sort by any
column.

The verdict is `untrusted` when a capture is not finalised, shut down uncleanly,
omitted events, reached its output limit, had a writer failure, or recorded a
gap; `partial` when any family is partial; otherwise `complete`.

## Component boundaries

The capture list, the capture bar, the trust banner, the view rail, and each
view are keyed, memoized boundaries directly under the root. Inside
Interactions, the triggers table, the cycle list, each cycle row (keyed by its
cycle), and the inspector are boundaries of their own. Every boundary compares
only what it draws: the capture's revision, which names one reading of it, and
the few fields of navigation it reads. A view that changes only itself, such as
sorting a table or choosing a phase, renders only that view. A change a sibling
must show, such as choosing a trigger, is delegated to the nearest boundary that
holds both. Work that needs a handle only the root holds, such as reading a
cycle, is a request the root fulfils, so while it is read the window restages
only its header and every view is kept.

## Running

```sh
python3 build.py
python3 examples/observatory/generate_fixture.py
roc build --output=observatory examples/observatory/main.roc
./observatory -- --host-cap-dir examples/observatory/fixture/captures
./observatory -- --host-cap-file examples/observatory/fixture/captures/counter-counting.rgstats
```

`--host-cap-dir` provisions the folder the folder chooser answers with, and
`--host-cap-file` the file "Open capture…" answers with. Any folder of
captures works, such as `.test-out/specs/<stamp>/examples/counter/specs`.

The fixture script runs real specifications of the Counter and Database Browser
examples through `scripts/run_specs.py` and keeps their captures. From those it
derives an interrupted capture (the metadata a recorder leaves when its process
dies before finalisation), a capture that names schema 4, and a capture cut
short to one kilobyte. The scaling folders hold 10, 100, and 1,000 hard links to
the real captures. Nothing under `fixture/` is committed; `run_specs.py`
regenerates it when the recorder schema or the contents of any input change: the
generator, the specifications it runs and the applications they drive, the
platform, or the host's sources and locks.

## Not yet built

- One capture opens at a time; there is no drop target or recent list.
- No distribution chart, frames, timeline, scaling, or comparison view.
- A `—` shows its family's status and reason beside it, not on hover.
- Steps are listed by line number and kind; the specification source is not
  shown beside them, and "Show step" marks the step rather than scrolling the
  list to it.

## Specifications

Twenty-two specifications run on the semantic runner. They cover the first
frame, a single chosen capture and its withdrawal, a dismissed, a refused, and
a wrongly typed file choice, a refused folder grant, the capture list with each health badge, the
schema gate, a file that is not a database, the overview's identity, chips, and
honest tiles, an untrusted capture's banner on every view, the health sheet,
spec results across runs, the triggers table across phases, sorting by column,
the cycle list and its trigger filter, the cycle inspector with a dash that
opens Health, a cycle's step in the Spec view, and the memory view.
Sorting, choosing a trigger or phase, opening a view, and inspecting a cycle
also pin which boundaries render, and how many nodes the host restages.
`scale-10.scm`, `scale-100.scm`, and `scale-1000.scm` are the scaling cases: each opens a
benchmark output folder of that many real captures. `window-tour.scm` drives
the real window through every view and photographs each, and
`window-open-capture.scm` photographs the start page and a capture opened from
a single file.
