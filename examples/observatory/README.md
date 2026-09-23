# Observatory

A read-only explorer for `.rgstats` captures, the SQLite databases the roc-gui
recorder writes for every specification, benchmark, and recorded session. It
opens one capture from a single-file grant, offering only `.rgstats` files, or
takes a directory grant, lists every capture in the folder with its identity and
a health badge, and opens one. Either way the capture is read through the
platform's ordinary SQLite capability. It queries the capture's tables itself and depends on no other
tool.

A capture of any schema other than 20 is refused with its reason before a single
table is read. An open capture always shows its identity and health first: a
bar of chips for backend, detail, schema, finalisation, shutdown, recording
gaps, and timing quality, and a banner on every view when the capture cannot be
trusted. Eight views follow:

- **Overview**: identity from `metadata`, and tiles for outcome, slowest
  trigger, median cycle, frames over budget, skip rate, and verdict.
- **Interactions**: the triggers table, cycles grouped by trigger and patch kind
  within one measurement phase, with count, minimum, median, maximum, and
  interquartile range. Below it, every cycle of the phase, slowest first, each
  with a bar of callback, validate, apply, and unattributed time; choosing a
  trigger narrows the list to its cycles, and Slowest and Fastest jump to either
  end. The list builds only the rows near its viewport and reads the capture a
  page of cycles at a time as the viewport reaches them, so a capture of any
  length opens in the time its first page takes. Pressing a cycle opens the
  inspector: a waterfall of the cycle's time through the Roc callback and its
  five work spans, validate, and apply with graph and GPUI apply, where the time
  no owner attributed is shown as `unattributed` and a Σ check proves the parts
  sum to the cycle; the eleven component work kinds; graph and keyed work; and
  the allocations of each span. A cycle driven by a specification step opens
  the Spec view with its step list scrolled to that step. Between the triggers
  table and the cycle list, a histogram counts the listed cycles in octave
  buckets of duration, with median and max markers; hovering a bucket reads
  out its range and count, and pressing it lists only its cycles. Warmup runs
  are excluded.
- **Frames**: a strip chart of every drawn frame, one stacked bar of layout
  request, prepaint, and paint per frame against a 30, 60, or 120 Hz budget.
  A capture of more frames than the strip's 240 columns draws the costliest
  frame of each column, so a slow frame is never averaged away, and the wheel
  zooms into the frames around the pointer. Layout solve and presentation are
  drawn as unavailable bands with their reasons. Hovering a frame reads out its
  stages; pressing it opens its own work. Below the strip: native renders and
  elements created for every node kind, including the keyed container; GPUI's
  nineteen frame-work counts grouped as cached and replayed, fresh, and moved
  and rebased, with the share of scene operations replayed; and each virtual
  list's last pass, flagged when it materialised more than three times what it
  showed, with a chart of its passes. A semantic-headless capture draws no
  frame, and the view says so with the family's status and reason.
- **Spec**: the runs, a run selector, and the selected run's steps with their
  status, duration, and expected and observed values, in a list read a page at
  a time as it scrolls.
- **Memory**: allocations by trigger and span (calls and bytes, mean, maximum,
  and total), each run's Roc allocation lifecycle, and each run's user and
  system CPU and peak and current RSS, with a bar of peak RSS per run.
- **Health**: the verdict and the rule that produced it, every measurement
  family, recording gaps, recorder health, every identity key, and the declared
  unavailable sources.
- **Compare**: the comparability sheet of the baseline and the open capture,
  every gate key with both values and whether it passed, and the A/A capture
  chosen from the folder. Pressing "Set as baseline" makes the open capture the
  baseline for every other capture opened after it, and a bar under the capture
  bar names it on every view. While the pair is comparable, the triggers
  table, the cycle inspector, and Memory show each value's Δ and ratio against
  the baseline, and the triggers table orders by |Δ|; with an A/A capture, a Δ
  no larger than the A/A spread of the same value is marked within noise. An
  incomparable pair shows its failing keys and no delta anywhere.
- **Scaling**: captures chosen from the folder as a scaling set, the gate that
  admits or refuses them with the failing key, each capture's count
  assertions, and every trigger's mean callback, validate, graph apply, and
  span allocation as an observed ratio from scale to scale against the scale
  ratio. A verdict of linear, sub-linear, or super-linear is given only when
  every step has evidence, and an A/A capture at one of the set's scales marks
  the ratios within its noise band. A log-log chart per trigger and metric
  plots each mean against its scale beside a dashed line of linear growth.

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

The capture list, the capture bar, the trust banner, the baseline bar, the view rail, and each
view are keyed, memoized boundaries directly under the root. Inside
Interactions, the triggers table, the cycle list, each cycle row (keyed by its
cycle), and the inspector are boundaries of their own, and every long list
builds its rows as a boundary of its own. Every boundary compares only what it
draws: the capture's revision, which names one reading of it, the read that
produced a list's page of rows, and the few fields of navigation it reads. A
view that shows deltas also compares the revisions of the baseline and the A/A
capture, so setting a baseline renders the baseline bar and the views that
draw a delta, and no other. A view that changes only itself, such as
sorting a table or choosing a phase, renders only that view. A change a sibling
must show, such as choosing a trigger, is delegated to the nearest boundary that
holds both. Work that needs a handle only the root holds, such as reading a
cycle or a page of cycles, is a request the root fulfils, so while it is read
the window restages only its header and every view is kept. A list whose page
is being read holds the places of its unread rows.

## Running

```sh
python3 build.py
python3 examples/observatory/generate_fixture.py
roc build --output=observatory examples/observatory/main.roc
./observatory -- --host-cap-dir examples/observatory/fixture/captures
./observatory -- --host-cap-dir examples/observatory/fixture/compare
./observatory -- --host-cap-file examples/observatory/fixture/captures/counter-counting.rgstats
```

`--host-cap-dir` provisions the folder the folder chooser answers with, and
`--host-cap-file` the file "Open capture…" answers with. Any folder of
captures works, such as `.test-out/specs/<stamp>/examples/counter/specs`.

The fixture script runs real specifications of the Counter and Database Browser
examples through `scripts/run_specs.py` and keeps their captures. From those it
derives an interrupted capture (the metadata a recorder leaves when its process
dies before finalisation), a capture that names schema 4, and a capture cut
short to one kilobyte. `compare/` holds the Database Browser's 100, 1,000,
and 10,000 row benchmarks from one executable, two more runs of the 100 row
benchmark by that executable (A/A captures), and one run with two jobs, which
the recorder marks contended. The scaling folders hold 10, 100, and 1,000 hard links to
the real captures, and `session/` holds one long capture: a Database Browser
browsing session of exactly 10,000 cycles in one run, written out as a
specification and recorded at full detail by the Database Browser itself.
`window/` holds two captures of the Database Browser's real window: its own
`window-rows` specification, and a generated session that scrolls its ten
thousand rows until at least 1,000 frames are drawn, in about half a minute
of window time. Nothing under `fixture/` is committed; `run_specs.py`
regenerates it when the recorder schema or the contents of any input change: the
generator, the specifications it runs and the applications they drive, the
platform, or the host's sources and locks.

## Not yet built

- One capture opens at a time; there is no drop target or recent list.
- No timeline, and the scaling charts have no metric selector.
- A `—` shows its family's status and reason beside it, not on hover.
- Steps are listed by line number and kind; the specification source is not
  shown beside them.

## Specifications

Thirty-three specifications run on the semantic runner. They cover the first
frame, a single chosen capture and its withdrawal, a dismissed, a refused, and
a wrongly typed file choice, a refused folder grant, the capture list with each health badge, the
schema gate, a file that is not a database, the overview's identity, chips, and
honest tiles, an untrusted capture's banner on every view, the health sheet,
spec results across runs, the triggers table across phases, sorting by column,
the cycle list and its trigger filter, the cycle inspector with a dash that
opens Health, a cycle's step in the Spec view, the memory view, the duration
distribution and its bucket filter, the Frames view of a window capture with
its hover and a pressed frame, the Frames view of a headless capture, the
comparability sheet of an A/A pair and of a contended run, a baseline's deltas
in every view and the A/A capture that bounds them, and a scaling set with its
refusals and its noise band. The comparison and scaling specifications also
pin how many SQLite connections are live: one each for the open capture, the
baseline, the A/A capture, and every capture of a scaling set.
Sorting, choosing a trigger or phase, opening a view, and inspecting a cycle
also pin which boundaries render, and how many nodes the host restages.
`scale-10.scm`, `scale-100.scm`, and `scale-1000.scm` are the scaling cases for a
folder: each opens a benchmark output folder of that many real captures, and
`scale-compare.scm` compares two of a thousand and chooses a scaling set among
them.
`scale-session.scm` is the scaling case for one long capture: it opens the
10,000-cycle session and jumps from one end of its cycle list to the other, and
`session-step.scm` opens a step ten thousand steps into its run.
`frames-scale.scm` is the scaling case for the frame strip: it opens the
session of at least 1,000 frames and zooms into it with the wheel.
`window-session.scm` scrolls the same list four thousand cycles down in the
real window and photographs the late step. `window-tour.scm` drives
the real window through every view and photographs each, and
`window-open-capture.scm` photographs the start page and a capture opened from
a single file. `window-compare.scm` photographs the comparability sheet of a
comparable and an incomparable pair, the triggers table with its deltas, and
a scaling set's gate, ratios, and chart. `window-frames.scm` moves the
window's own pointer over the frame strip and the distribution and scrolls its
wheel, and photographs each.
