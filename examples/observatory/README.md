# Observatory

A read-only explorer for `.rgstats` captures, the SQLite databases the roc-gui
recorder writes for every specification, benchmark, and recorded session. It
takes a directory grant, lists every capture in the folder with its identity and
a health badge, and opens one through the platform's ordinary SQLite
capability. It queries the capture's tables itself and depends on no other
tool.

A capture of any schema other than 19 is refused with its reason before a single
table is read. An open capture always shows its identity and health first: a
bar of chips for backend, detail, schema, finalisation, shutdown, recording
gaps, and timing quality, and a banner on every view when the capture cannot be
trusted. Four views follow:

- **Overview**: identity from `metadata`, and tiles for outcome, slowest
  trigger, median cycle, frames over budget, skip rate, and verdict.
- **Interactions**: the triggers table, cycles grouped by trigger and patch kind
  within one measurement phase, with count, minimum, median, maximum, and
  interquartile range. Warmup runs are excluded.
- **Spec**: the runs, a run selector, and the selected run's steps with their
  status, duration, and expected and observed values, in a virtual list.
- **Health**: the verdict and the rule that produced it, every measurement
  family, recording gaps, recorder health, every identity key, and the declared
  unavailable sources.

Every number belongs to a measurement family. A family whose status is not
`complete` is shown as `—` with its status and reason, never as zero. The
verdict is `untrusted` when a capture is not finalised, shut down uncleanly,
omitted events, reached its output limit, had a writer failure, or recorded a
gap; `partial` when any family is partial; otherwise `complete`.

## Running

```sh
python3 build.py
python3 examples/observatory/generate_fixture.py
roc build --output=observatory examples/observatory/main.roc
./observatory -- --host-cap-dir examples/observatory/fixture/captures
```

`--host-cap-dir` provisions the folder the chooser answers with. Any folder of
captures works, such as `.test-out/specs/<stamp>/examples/counter/specs`.

The fixture script runs real specifications of the Counter and Database Browser
examples through `scripts/run_specs.py` and keeps their captures. From those it
derives an interrupted capture (the metadata a recorder leaves when its process
dies before finalisation), a capture that names schema 4, and a capture cut
short to one kilobyte. The scaling folders hold 10, 100, and 1,000 hard links to
the real captures. Nothing under `fixture/` is committed; `run_specs.py`
regenerates it when the recorder schema or the generator's inputs change.

## Not yet built

- One capture opens at a time, only from a granted folder; there is no single
  file chooser, drop target, or recent list.
- No sorting of the capture list or the triggers table, and no cycle list,
  cycle inspector, distribution chart, frames, timeline, memory, scaling, or
  comparison view.
- A `—` shows its family's status and reason beside it, not on hover, and does
  not open Health at that family.
- Steps are listed by line number and kind; the specification source is not
  shown beside them.

## Specifications

Thirteen specifications run on the semantic runner. They cover the first frame,
a refused folder grant, the capture list with each health badge, the schema
gate, a file that is not a database, the overview's identity, chips, and honest
tiles, an untrusted capture's banner on every view, the health sheet, spec
results across runs, and the triggers table across phases. `scale-10.scm`,
`scale-100.scm`, and `scale-1000.scm` are the scaling cases: each opens a
benchmark output folder of that many real captures. `window-tour.scm` drives
the real window through every view and photographs each.
