# Observatory

A read-only explorer for `.rgstats` captures, the SQLite databases the roc-gui
recorder writes for every specification, benchmark, and recorded session. It
opens one capture from a single-file grant, offering only `.rgstats` files, or
takes a directory grant, lists every capture in the folder with its identity and
a health badge, and opens one. Either way the capture is read through the
platform's ordinary SQLite capability. It queries the capture's tables itself and depends on no other
tool.

A capture of any schema other than 25 is refused with its reason before a single
table is read. An open capture always shows its identity and health first: a
bar of chips for backend, detail, schema, finalisation, shutdown, recording
gaps, and timing quality, and a banner on every view when the capture cannot be
trusted or is not yet finalised.

Several captures stay open at once, one tab each above the capture bar, and
the baseline's tab is marked `◆`. `+` keeps the capture on screen open in its
tab and lists the folder to choose another; pressing a tab, or Left and Right
while focus is in the strip, brings its capture back at the view, filter,
selection, and list positions it was left at, without reading it again. A
capture still being recorded is read again when it comes back, and watched
again. Closing a tab, with its `×` or Delete, closes its capture and shows its
neighbour; "‹ Captures" closes the capture on screen and lists the folder.

Beside every view is the inspector, which shows the detail of whatever that
view has selected: the cycle in Interactions, the pressed frame in Frames and
in the Timeline, and the chosen line's or step's steps in Spec. Its divider
drags, or moves with the arrow keys while it has focus, to widen or narrow it,
and folds it away; Enter on the divider or "Hide" folds it, and it comes back
at the width it had. Pinning it keeps the selection of the view it was pinned
on beside every other view until it is unpinned. Nine views follow:

- **Overview**: identity from `metadata`, and tiles for outcome, slowest
  trigger, median cycle, frames over budget, skip rate, and verdict.
- **Interactions**: the triggers table, cycles grouped by trigger and patch kind
  within one measurement phase, with count, minimum, median, maximum, and
  interquartile range. Below it, every cycle of the phase, slowest first, each
  naming the element it reached by node kind and structural identity, never by
  its text, and each with a bar of callback, validate, apply, and unattributed time; choosing a
  trigger narrows the list to its cycles, and Slowest and Fastest jump to either
  end. The list builds only the rows near its viewport and reads the capture a
  page of cycles at a time as the viewport reaches them, so a capture of any
  length opens in the time its first page takes. Pressing a cycle opens the
  inspector: a waterfall of the cycle's time through the Roc callback and its
  five work spans, validate, and apply with graph and GPUI apply, where the time
  no owner attributed is shown as `unattributed` and a Σ check proves the parts
  sum to the cycle; the eleven component work kinds; graph and keyed work; and
  the allocations of each span, beside the view. A cycle driven by a specification step opens
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
  stages; pressing it opens its own work and the cycles its owner recorded it
  was the first to draw, each of which opens in the inspector. Below the strip: native renders and
  elements created for every node kind, including the keyed container; GPUI's
  nineteen frame-work counts grouped as cached and replayed, fresh, and moved
  and rebased, with the share of scene operations replayed; and each virtual
  list's last pass, flagged when it materialised more than three times what it
  showed, with a chart of its passes. A semantic-headless capture draws no
  frame, and the view says so with the family's status and reason.
- **Timeline**: what happened, in order. Lanes of cycles by trigger, drawn
  frames, and virtual-list passes share the capture's one process-relative
  clock. Each lane divides the span on screen into 360 columns and keeps the
  longest cycle, costliest frame, or largest pass of each, so a capture of any
  length draws the same number of marks. The wheel zooms around the instant
  under the pointer and pans sideways, hovering a mark reads it out, pressing a
  frame lists the cycles it was the first to draw and marks them in their
  lanes, and pressing a cycle opens it in the inspector. A frame with no
  recorded link says "cause not recorded", with the linkage family's status
  when it is not complete, and is never tied to the nearest cycle. A
  semantic-headless capture draws its cycles and shows the frame and list
  lanes as not recorded, with their reasons.
- **Spec**: the runs, a run selector, and the selected run's steps with their
  status, duration, and expected and observed values, in a list read a page at
  a time as it scrolls. "Open spec sources…" takes a folder of `.scm`
  specifications. A capture records its specification only as `spec_name` and
  `spec_hash`, never as a path, so Observatory asks the host for the SHA-256 of
  each `.scm` file in the folder and takes the one whose hash is `spec_hash`.
  That file is shown line by line, highlighted, with a gutter of each line's
  step status, duration, cycle count, and patch kind for the selected run or
  the median across the samples. A failing line is marked, with its diagnostic
  and its assertions' expected and observed values beneath it, mismatches
  marked; pressing a line number opens its steps in the inspector, with every
  sample's own values beside the median. A file that declares the capture's
  test but hashes differently has changed since the capture: a banner says so,
  no number is placed on its lines, and the steps stay listed by line. The
  source's lines are built only near the viewport, so a specification of ten
  thousand lines opens as fast as a short one.
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
`complete` is shown as `—` with its status and reason, never as zero; hovering
a `—` shows its family, status, and reason, and pressing it opens Health at
that family. Values the capture records per
cycle follow the same rule: spans and their allocations are `—` for a callback
whose spans were not valid, component work is `—` for a cycle with no component
observation (and an absent kind is zero only for one with it), GPUI apply is
`—` when it was not recorded, and a run with no end snapshot has no CPU, RSS,
or allocation change. The capture list and the triggers table sort by any
column.

The window is light or dark as the desktop asks, and follows it when it
changes; the palette's Theme commands choose light or dark over it, or follow
the system again. Every colour is a light and dark pair, so the scales keep
their order and their contrast with the ground in both.

The keyboard reaches everything. Ctrl+K opens a command palette that finds, as
you type, the commands (open a folder or a capture, back, forward, set or clear
the baseline, close the capture, choose a theme), the views, the folder's captures, and every
trigger of every phase; `cycle N` inspects the cycle with that ordinal in the
selected run and `step N` shows its step in Spec. Up and Down move the
highlight and Enter chooses it. Opening a cycle, its step, a frame, or a
palette target remembers the place left, and Alt+Left and Alt+Right, or the
Back and Forward buttons in the header, move over those places, restoring the
view, what it had selected, and where its lists were. Ctrl+1 to Ctrl+9 show
the views in the rail's order. In Interactions, J and K inspect the next and
the previous cycle of the list, bringing it into view, and I moves keyboard
focus into the inspector.

The triggers, cycles, waterfall, allocations by trigger, steps, and measurement
families tables each have a Copy button, which puts the rows the table shows on
the clipboard as Markdown, each with the family its values come from, that
family's status, and its reason, so a `—` pasted into a review still says why.

The verdict is `withheld` while a capture is not finalised, since the families,
recorder health, and gaps a verdict rests on are written only then; `untrusted`
when a finalised capture shut down uncleanly, omitted events, reached its
output limit, had a writer failure, or recorded a gap; `partial` when any family
is partial; otherwise `complete`.

## A capture that changes

A capture its recorder has not finalised is marked **Recording**, its shutdown
and gaps read as not yet known, and every verdict that needs finalisation, on
Health, Compare, and Scaling, says "capture not yet finalised". While it is
open it is watched: each commit its recorder makes wakes the watch, and when
the commit wrote rows past the largest ids read, ended a run, or finalised the
capture, Observatory reads it again through the same connection, so new
cycles, frames, and steps appear in the lists on screen, at the phase, filter,
and run they show. A chip "● live" says the watch is running; it ends when the
capture is finalised, closed, or its grant is withdrawn. The capture's
`capture_id` tells a file that grew from a file replaced by another capture.

A folder is watched too. When a capture in it is created, removed, or replaced,
the folder is listed again, and only the captures the watch named are read
again. When the open capture's file now holds another capture, the capture bar
says "Capture changed" and offers Reload, which reads it where the person was:
the view, the phase, a trigger filter, the run by its phase and sample, and the
inspected cycle by its run, trigger, and ordinal.

Every read of the open capture has a task key of its kind: a page of cycles, a
page of steps, the inspected cycle, a frame, the frame strip, and the timeline.
Paging or inspecting again supersedes the read in flight, which the host
interrupts where its query runs, so a quick sweep through a long capture reads
only where it stops. The watch of a capture being recorded has a key too:
opening another capture supersedes it, and closing the capture cancels it, so a
closed capture's watch ends without a completion.

## Component boundaries

The capture list, the tabs, the capture bar, the trust banner, the baseline bar, the view rail, each
view, and the inspector are keyed, memoized boundaries directly under the root.
The inspector's width is the root's own state, so dragging its divider renders
the window alone and compares every boundary, whatever the views beside it
hold. Inside Interactions, the triggers table, the cycle list, and each cycle
row (keyed by its cycle) are boundaries of their own, and every long list
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
./observatory -- --host-cap-file examples/observatory/fixture/failing/counter-regressed.rgstats --host-cap-dir examples/observatory/fixture/sources
./observatory -- --host-cap-dir examples/observatory/fixture/captures --host-cap-clipboard
```

To watch a recording, record an application and open its capture while it
runs:

```sh
./counter --host-stats-output=counter-session.rgstats &
./observatory -- --host-cap-file counter-session.rgstats
```

`--host-cap-dir` provisions the folder the folder chooser answers with, and
`--host-cap-file` the file "Open capture…" answers with. `--host-cap-clipboard`
grants the clipboard Copy writes to; without it, Copy says how to grant one. Any folder of
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
of window time. `sources/` is a folder of specification sources to grant to
the Spec view: the specifications behind `captures/`, the session's, and a copy
of the Counter's counting specification that expects one render more than the
Counter does, whose failing run is `failing/counter-regressed.rgstats`.
`sources-edited/` holds the counting specification with a comment added after
its capture was recorded. Nothing under `fixture/` is committed; `run_specs.py`
regenerates it when the recorder schema or the contents of any input change: the
generator, the specifications it runs and the applications they drive, the
platform, or the host's sources and locks.

## Not yet built

- There is no drop target or recent list, and tabs cannot be dragged into
  another order.
- The scaling charts have no metric selector.
- Only six tables have Copy; the Overview tiles, the inspector's work and
  allocation sections, the run lifecycle and process resources, the Frames and
  Timeline tables, and the Compare and Scaling sheets have none.
- The palette does not find a frame or a source line (`frame N`, `line N`).
- A finalised capture chosen as one file is not watched, so its replacement
  is not offered for reloading.
- While a capture grows, the Timeline keeps the span it last read until it is
  shown again.

## Specifications

Fifty-five specifications run on the semantic runner. They cover the first
frame, a single chosen capture and its withdrawal, a dismissed, a refused, and
a wrongly typed file choice, a refused folder grant, the capture list with each health badge, the
schema gate, a file that is not a database, the overview's identity, chips, and
honest tiles, an unfinalised capture's withheld verdicts on every view, a
capture being recorded growing as its recorder commits and its watch ending
when its grant is withdrawn or cancelled when it is closed, a folder chosen
again superseding the watch of the one listed before, a replaced capture offered for reloading and
reloaded in place, the health sheet,
spec results across runs, the triggers table across phases, sorting by column,
the cycle list and its trigger filter, the cycle inspector with a dash that
opens Health, a cycle's step in the Spec view, the specification source
found by its hash and annotated with one run and with the median of its
samples, a failing step's diagnostic and assertion table on its line, and a
changed specification's banner, the memory view, the duration
distribution and its bucket filter, the Frames view of a window capture with
its hover and a pressed frame, the Frames view of a headless capture, the
Timeline of a window capture with its hover, zoom, and a pressed cycle, a
frame's recorded causes followed from the strip to the inspector, the
Timeline of a headless capture, the
comparability sheet of an A/A pair and of a contended run, a baseline's deltas
in every view and the A/A capture that bounds them, and a scaling set with its
refusals and its noise band, the command palette finding captures, views,
triggers, a cycle, and a step, back and forward over jumps, the view and
inspector shortcuts, copying every table that has Copy with and without a
clipboard grant, a `—` whose hover says why, captures open in tabs that each
keep their own view (`tabs.scm`), and the inspector resized, folded, and pinned
(`inspector-pane.scm`). The comparison and scaling specifications also
pin how many SQLite connections are live: one each for the open capture, the
baseline, the A/A capture, and every capture of a scaling set.
Sorting, choosing a trigger or phase, opening a view, and inspecting a cycle
also pin which boundaries render, and how many nodes the host restages.
`watch-scale.scm` is the scaling case for a watched folder: one capture of a
folder of 100 is replaced, and only it is read again.
`scale-10.scm`, `scale-100.scm`, and `scale-1000.scm` are the scaling cases for a
folder: each opens a benchmark output folder of that many real captures, and
`scale-compare.scm` compares two of a thousand and chooses a scaling set among
them.
`scale-tabs-10.scm` and `scale-tabs-50.scm` are the scaling cases for tabs:
each opens that many captures, one tab each, and switches back to the first,
whose work is the same whatever the number of tabs open. `scale-divider.scm`
drags the inspector's divider beside the 10,000-cycle session's cycle list and
renders the window alone.
`scale-session.scm` is the scaling case for one long capture: it opens the
10,000-cycle session and jumps from one end of its cycle list to the other, and
`session-step.scm` opens a step ten thousand steps into its run.
`scale-source.scm` is the scaling case for the annotated specification: it
annotates the session's own specification of ten thousand lines, building only
the lines near the viewport, and opens a late cycle's step on its line.
`frames-scale.scm` is the scaling case for the frame strip: it opens the
session of at least 1,000 frames and zooms into it with the wheel, and
`timeline-scale.scm` opens the same session on the Timeline and zooms and pans
it.
`window-session.scm` scrolls the same list four thousand cycles down in the
real window and photographs the late step. `window-tour.scm` drives
the real window through every view and photographs each, and
`window-open-capture.scm` photographs the start page and a capture opened from
a single file. `window-replaced.scm` photographs the capture bar's offer to
reload a replaced capture and the capture read again in the same place. `window-compare.scm` photographs the comparability sheet of a
comparable and an incomparable pair, the triggers table with its deltas, and
a scaling set's gate, ratios, and chart. `window-frames.scm` moves the
window's own pointer over the frame strip and the distribution and scrolls its
wheel, and photographs each, and `window-timeline.scm` does the same over the
Timeline. `window-keyboard.scm` types into the palette in the real window,
walks to a cycle and into its inspector by keyboard, copies its waterfall, and
photographs a `—`'s hover. `window-spec-source.scm` photographs a failing
run's annotated specification with its diagnostic and assertion table, and
`window-spec-median.scm` a benchmark's at the median of its samples.
`window-shell.scm` opens two captures in tabs, drags the inspector's divider
with the window's own pointer, folds it by keyboard, and photographs each.
`theme.scm` follows the system's scheme as it changes and chooses one over it
from the palette, and `window-theme.scm` photographs the capture list, the
Overview, Interactions with each cycle's target, and a hovered Timeline in the
light scheme and then the dark.
