# Observatory: requirements

Observatory is a desktop application for exploring how a roc-gui application performs. It
opens `.rgstats` captures, the SQLite databases the roc-gui recorder writes for every
specification, benchmark, and recorded interactive session. It answers two questions together:
*how does this application perform?* and *can I trust that answer?*

This document holds the user stories and placeholder wireframes for the ideal application.
Unfinished work is tracked in `wip/issues-backlog.md` under "Observatory example", not here.

## 1. Purpose

- **Explore roc-gui performance.** Observatory opens a capture through the platform's SQLite
  capability and queries its tables directly. It owns every query and every rule it applies:
  evidence status, trust, comparability, and scaling. It does not depend on any other tool.
  From one navigable application, a user picks an interaction, sees where its time went, sees
  what the frame rebuilt, and compares it against a baseline.
- **Pilot for the Roc Observatory viewer.** The Roc Observatory desktop viewer reads `.rocobs`
  captures of Roc programs and needs most of the same platform features: open a capture,
  honest evidence chrome, virtualized sortable tables, drill-down, hover cards, charts, A/B
  comparison, annotated source, and live reload. This application builds those features against
  data that already exists. Every story is tagged:
  - **[shared]**: the same user experience is required by the `.rocobs` viewer.
  - **[rgstats]**: specific to roc-gui captures.
- **Dogfooded.** Observatory is a roc-gui application, so it records its own `.rgstats`. Its
  scaling case is opening and navigating a large, real capture.

## 2. Principles

1. **Honest or absent.** A number is shown only when its measurement family is `complete`.
   Otherwise the cell shows `—`, and its status and reason are one hover away. Unmeasured is
   never zero. A sparse table's missing row counts as zero only where the capture's own
   recorded flag says so.
2. **Totals decompose.** Every aggregate expands into the parts that sum to it. A remainder that
   no owner measured is shown as *unattributed*, never folded into a neighbour.
3. **No links the schema does not declare.** Rows from two tables are related only through a
   declared key. When the recorder does not link two things (for example a frame and the cycle
   that caused it), the application says so rather than guessing from ordering.
4. **Comparison is a mode.** A baseline can be applied to every view. It is not a separate
   report.
5. **Evidence first, then numbers.** Identity, finalisation, and health are always visible
   before any measurement.
6. **Keyboard-first, mouse-complete.** Every action is reachable from the command palette and
   by pointer.
7. **Privacy holds.** Captures contain no application text, paths, hostnames, or user
   identity. The application presents only what the capture contains, and anything it copies
   out carries the same guarantee.

## 3. Personas

| Persona | Wants to know |
|---|---|
| **App author**: builds a Roc application on roc-gui | Which interaction is slow? Is it my update, my render, or the platform? Am I rendering more than I need to? |
| **Platform contributor**: changes the host or the Roc platform | Did graph, native, or component work regress? Does it still scale linearly? Is the capture sound? |
| **Reviewer**: receives two captures in a pull request | Are these comparable? Is the difference beyond noise? |

## 4. Key questions

Each question maps to the evidence that answers it and the view where the answer lives. Evidence
names tables and columns of capture schema 23, as defined by the recorder in
`crates/host/src/observatory.rs` and described in `docs/observatory.adoc`. Items marked
**E*n*** need recorder evidence listed in [§8](#8-evidence-requests).

| # | Question | Evidence | View |
|---|---|---|---|
| Q1 | Can I trust this capture? | `metadata.final_state`, `clean_shutdown`, `timing_quality`; `recorder_health`; `recording_gaps`; `measurement_status` | Capture bar, Health |
| Q2 | What was captured, and on what? | `metadata` identity: `app_name`, `spec_name`, `spec_hash`, `backend`, `effective_detail`, `benchmark_*`, `target_profile`, `host_commit`, `host_dirty`, `cpu_model` | Overview |
| Q3 | Did it pass, and where did it fail? | `runs.outcome`, `steps` (`source_line`, `kind`, `status`, `diagnostic`, expected/observed), `*_counter_assertions`, `component_work_assertions` | Spec |
| Q4 | Which interactions are slow? | `cycles` by `trigger`, `measurement_phase`, `patch_kind`; `duration_ns` distribution | Interactions |
| Q5 | Where did one cycle's time go? | `cycles.roc_callback_ns`, `validate_ns`, `apply_ns`, `graph_apply_ns`, `gpui_apply_ns`; `roc_work_spans` | Cycle inspector |
| Q6 | Why did it re-render so much? | `component_work_counts` (rendered, compared, skipped, mounted, retired, …); `cycles.staged_nodes`, `removed_nodes`, `keyed_*`; E5 | Cycle inspector |
| Q7 | Is it allocating? | `roc_work_spans` allocation columns; `runs` start/end Roc allocation counters | Memory |
| Q8 | Are frames within budget, and what did they rebuild? | `gpui_frames`; `gpui_native_work`; `gpui_frame_work`; E1, E2 | Frames |
| Q9 | Is the virtual list actually virtualizing? | `virtual_list_frames`; E3 | Frames › Lists |
| Q10 | Does it scale? | several captures of one app and `executable_hash` at different `benchmark_scale`; `cycles` per trigger; `steps` scale checks (`expect-count`) | Scaling |
| Q11 | Did my change help, and is it beyond noise? | `metadata` identity of both captures; `cycles` per trigger; an A/A pair of captures for the noise bound | Compare |
| Q12 | What did the process cost? | `runs` CPU and RSS start/end snapshots | Memory › Process |
| Q13 | What happened, in order? | E1, E2, E4 | Timeline |

## 5. User stories

Each story is written as *As a …, I want …, so that …* and followed by acceptance criteria.
Criteria name semantic locators (`label`s), so each story becomes an `.scm` specification
directly. `(role button :name "Open capture")` is written below as **button "Open capture"**.

### J1: Open and orient

**US-1 [shared] Open a capture file.** As an app author, I want to open a single `.rgstats`
file, so that I can inspect the capture I just recorded.
- button "Open capture" presents the system file chooser, filtered to `.rgstats`.
- The capture opens as a tab named by its file name, and the capture bar shows backend, detail,
  schema, and health chips (US-6).
- The file is opened read-only, and the application never writes to a capture.

**US-2 [shared] Open a folder of captures.** As a platform contributor, I want to open a folder
of captures and see them listed, so that I can pick the run I care about from a benchmark output
directory.
- list "Captures" shows one row per capture: file name, app, spec, backend, scale, detail, and a
  health badge.
- The list is virtualized and sortable by each column, and it stays responsive with thousands of
  captures.
- Enter or a double press opens the capture. Selecting two rows offers button "Compare".

**US-3 [shared] Recent captures.** As an app author, I want recently opened captures and folders
listed on the start page, so that I return to my work without choosing again.
- list "Recent" survives restart through a remembered grant.
- An entry whose grant or file is gone is shown as unavailable with its reason, and it can be
  removed.

**US-4 [shared] Drop to open or compare.** As a reviewer, I want to drop capture files onto the
window, so that opening two captures from a pull request takes one gesture.
- Dropping onto the start page opens the capture. Dropping onto an open capture offers
  "Open" or "Compare with this capture".

**US-5 [shared] Refuse unsupported schemas.** As any user, I want an unsupported capture refused
with a clear reason, so that I never read numbers through the wrong schema.
- Opening a capture with a different `schema_version` shows
  "Schema 4 is not supported; Observatory reads schema 23". Nothing is partially rendered.

### J2: Trust

**US-6 [shared] Health is always visible.** As any user, I want finalisation and health in view
at all times, so that I never read an incomplete capture as complete.
- The capture bar shows chips for final state, clean shutdown, recording gaps, timing quality,
  backend, and detail.
- A capture that is untrusted (not finalised, unclean shutdown, writer failure, output limited,
  or omitted events) shows a banner at the top of every view, stating the cause.

**US-7 [shared] Every number knows its family.** As a platform contributor, I want every value to
carry its measurement family's status, so that `not_recorded` and `unavailable` are never
mistaken for zero.
- A cell from a family whose status is not `complete` renders `—`.
- Hovering any value shows its family, status, and reason. Pressing it opens Health at that
  family.
- A chart series from such a family is drawn as an empty band labelled with the status, not as a
  zero line.

**US-8 [shared] Health sheet.** As a platform contributor, I want one sheet with the capture's
complete health, so that I can judge a capture before trusting it.
- table "Measurement families" lists every `measurement_status` row: name, required detail,
  status, reason, rows recorded, omitted events.
- table "Recording gaps", section "Recorder health", section "Identity" (all metadata keys), and
  the `unavailable_sources` list.
- The verdict is one of `complete`, `partial`, `untrusted`, or `unsupported`. It is derived
  from `metadata`, `recorder_health`, and `measurement_status` by the rule stated on the sheet,
  and the same rule is the one `docs/observatory.adoc` defines for a complete capture.

### J3: Find the slow interaction

**US-9 [rgstats] Interactions by trigger.** As an app author, I want cycles grouped by trigger,
so that I can see which kind of interaction costs the most.
- table "Triggers" shows one row per `trigger` × `patch_kind`: cycles, min, median, max, spread,
  and a distribution sparkline.
- A phase filter (initialization, setup, measured, interactive) defaults to measured, or
  interactive for an interactive session.
- Sortable by every column. Selecting a row filters the cycle list (US-10).

**US-10 [shared] Slowest cycles.** As an app author, I want the individual slowest cycles listed,
so that I can open the worst case rather than an average.
- list "Cycles" is virtualized and ordered by duration by default. Each row shows run, ordinal,
  trigger, target, patch kind, duration, and a stacked bar of callback, validate, and apply time.
- Pressing a row opens the cycle inspector (US-13) without losing the list position.

**US-11 [rgstats] Distribution chart.** As a platform contributor, I want a histogram of cycle
durations per trigger, so that I can see bimodal behaviour a median hides.
- canvas "Duration distribution" draws a log-scaled histogram with median and max markers.
  Hovering a bucket shows its range and count, and pressing it filters the cycle list.

**US-12 [rgstats] What was pressed.** As an app author, I want each interactive cycle to identify
the element that caused it, so that "click, 180 ms" becomes "this button, 180 ms". *(E4)*
- The cycle row, the inspector, and the Timeline's hover readout show the target's node kind and
  a stable, non-textual node identity (`cycles.target_kind`, `cycles.target_identity`). A cycle
  no element caused, initialization or a task completion, shows "no target"; any other cycle
  whose target is not recorded shows "target not recorded".

### J4: Explain a cycle

**US-13 [shared] Cycle waterfall.** As an app author, I want one cycle's time decomposed, so that
I know whether my update, my render, or the platform dominates.
- section "Cycle" shows `duration_ns` as a waterfall. The Roc callback contains routing,
  application update, application render, component comparison, and platform lowering; then
  validate; then apply, containing graph apply and GPUI apply.
- The part of the callback not covered by a span, and the part of the cycle not covered by
  callback, validate, or apply, are shown as *unattributed*. A Σ check proves the parts sum to
  the total.
- When `roc_work_valid = 0`, the span breakdown shows `—` with the reason.

**US-14 [rgstats] Component work.** As an app author, I want the component work for a cycle, so
that I can see whether memoisation is doing its job.
- table "Component work" lists all eleven kinds, with the skip rate (skipped ÷ compared) shown
  with its numerator and denominator.
- When `component_work_recorded = 0`, every count is `—`. When it is 1, an absent kind is shown
  as 0.

**US-15 [rgstats] Graph work.** As a platform contributor, I want the graph and keyed work for a
cycle, so that I can connect a slow apply to the structure it touched.
- section "Graph work" shows staged, removed, live, retained, parent scanned, and validation
  visits, plus the keyed graph visits, original reads, first touches, native edits, and item
  entities created/retired/moved.

**US-16 [shared] Allocations per span.** As an app author, I want allocations attributed to the
span that performed them, so that I know which phase of my code allocates.
- table "Allocations" shows one row per span: allocation calls, allocated bytes, deallocation
  calls, reallocation calls, and reallocated bytes.

**US-17 [rgstats] Cycle to spec step.** As a platform contributor, I want to jump from a cycle to
the specification step that drove it, so that I can see the action in its script.
- For a cycle with a `step_ordinal`, button "Show step" opens the Spec view at the step's
  `source_line`. Interactive cycles have no step, and the button is absent.

**US-18 [rgstats] Which component rendered.** As an app author, I want component work attributed
to the components that performed it, so that I can find the one that re-renders needlessly.
*(E5)*
- The component work table expands into one row per component identity, and the rows sum to the
  cycle total.

### J5: The specification is the source

**US-19 [shared] Annotated specification.** As a platform contributor, I want the `.scm`
specification shown with per-step results beside each line, so that the script is the map of
the run.
- After a folder grant for the specification sources, the Spec view shows the spec file with a
  gutter per line: step status, duration, cycle count, and patch kind.
- The file's hash is compared with `metadata.spec_hash`. On mismatch, a banner says
  "Specification changed since capture", and no numbers are placed on lines. Steps are listed by
  `source_line` instead. This is the same rule the `.rocobs` viewer applies to Roc source.
- Without a source grant, steps are listed by line number and kind.

**US-20 [shared] Failures in place.** As an app author, I want a failing step's diagnostic and
expected-versus-observed values shown on its line, so that I can read the failure where it
happened.
- The failing line is highlighted, and an inline hint below it shows the diagnostic.
- Assertion vectors (`component_work_assertions`, and audio, clipboard, database, HTTP, and TCP
  counter assertions) are shown as expected/observed tables with mismatches highlighted.

**US-21 [rgstats] Runs and samples.** As a platform contributor, I want to switch between the
test run, warmups, and samples, so that I can see sample-to-sample variation.
- selector "Run" lists runs by phase and index. The gutter shows the selected run, or the median
  across samples, with the per-sample values in the inspector.

### J6: Frames

**US-22 [rgstats] Frame budget.** As an app author, I want each drawn frame's cost against a
frame budget, so that I can see jank.
- canvas "Frames" is a strip chart with one stacked bar per frame (layout request, prepaint,
  paint) and a budget line (60 Hz by default, selectable).
- Layout solve and presentation are drawn as an explicit *unavailable* band with their reasons,
  not omitted.
- A semantic-headless capture shows the Frames view as `not_recorded` with its reason.

**US-23 [rgstats] Native work by node kind.** As a platform contributor, I want native renders
and created elements per node kind, so that I can see which widgets a frame rebuilt.
- table "Native work" covers all node kinds (including keyed container), for both metrics, with
  total, max per frame, mean per frame, and the value for the selected frame.

**US-24 [rgstats] Replay versus fresh work.** As a platform contributor, I want GPUI cache replay
compared with fresh construction, so that I can tell whether a frame reused its scene.
- table "Frame work" lists all nineteen metrics, grouped as cached/replayed, fresh, and moved/
  rebased, with a replay share per frame.

**US-25 [rgstats] Virtual lists.** As an app author, I want each virtual list's visible,
materialised, recycled, and live entities, so that I know the list only builds what is on
screen.
- table "Virtual lists" shows one row per list, and a chart shows its passes over time.
- Entities materialised well beyond the visible count are flagged.

**US-26 [shared] Timeline.** As a platform contributor, I want cycles, frames, and list passes
on one time axis, so that I can see which action produced which frames. *(E1, E2, E3)*
- canvas "Timeline" shows lanes for cycles (by trigger), frames, and virtual-list passes on a
  shared clock. It supports zoom and pan, and hovering shows detail.
- A frame links to its causing cycle only through recorded linkage. Without it, the frame is
  marked "cause not recorded".

### J7: Memory and process

**US-27 [shared] Allocation profile.** As an app author, I want allocations summarised by trigger
and span, so that I can find the interaction that allocates most.
- table "Allocations by trigger" shows per trigger × span: calls and bytes (mean, max, total),
  plus the run lifecycle deltas.

**US-28 [rgstats] Process resources.** As a platform contributor, I want CPU and RSS per run, so
that I can see growth across samples.
- table "Runs" shows user and system CPU, and peak and current RSS per run, with a sample-index
  chart.

### J8: Scaling

**US-29 [shared] Scaling set.** As a platform contributor, I want to pick captures of one
specification at several scales and see how each trigger scales, so that I can find a
super-linear path.
- button "Scaling set" chooses captures. Captures that fail the gate (a different app or
  executable, non-isolated timing, more than one job, or the same scale) are refused with the
  failing key.
- canvas "Scaling" is a log-log chart per trigger (callback, validate, graph apply, and
  allocations) with a linear reference line.
- table "Scaling ratios" gives the observed ratio against the scale ratio, with a verdict
  (linear, sub-linear, super-linear) only when the evidence is complete.

**US-30 [rgstats] Noise band.** As a reviewer, I want an A/A capture shown as a noise band, so
that I don't call noise a regression.
- Choosing an A/A capture (the same executable run twice) draws its spread bound, and a ratio
  within the band is marked "within noise". The A/A capture must pass the same comparability
  gate as US-31, or it is refused with the failing key.
- The `expect-count` scale verification (checks, mismatches) is shown beside the chart.

### J9: Compare

**US-31 [shared] Comparability gate.** As a reviewer, I want to see whether two captures can be
compared, key by key, so that I trust or reject the comparison before reading a delta.
- sheet "Comparability" lists every gate key (schema, finalisation, spec hash, benchmark
  settings, backend, profile, OS, architecture, CPU, detail, jobs, buffer) with both values and
  pass/fail.
- An incomparable pair shows the reasons and no deltas anywhere.

**US-32 [shared] Baseline everywhere.** As a reviewer, I want to set a baseline once and see
deltas in every view, so that comparison is a mode rather than a report.
- button "Set as baseline" on a capture tab. Tables gain Δ and ratio columns and sort by |Δ| by
  default, and charts overlay the baseline in a secondary style.
- Deltas within a recorded A/A bound are marked "within noise".

### J10: Live session

**US-33 [shared] Watch a recording.** As an app author, I want to open a capture while my
application is still recording it, so that I can interact and watch the cost appear.
- An unfinalised capture shows chip "Recording", and new cycles and frames appear as they are
  written.
- Verdicts that need finalisation (health, scaling, compare) are withheld with "capture not yet
  finalised" until `final_state` is `complete`. *(E7)*

**US-34 [shared] Reload preserves place.** As an app author, I want a replaced capture reloaded
with my place kept, so that the record-and-inspect loop is fast.
- When the file is replaced, a chip "Capture changed, reload" appears. Reloading keeps the view,
  filters, and selection by stable keys (trigger, run phase, ordinal).

### J11: Navigate

**US-35 [shared] Command palette.** As any user, I want every command, view, trigger, cycle, and
step reachable by typing, so that the keyboard is enough.
- The palette opens with a shortcut and fuzzy-matches commands, views, captures, triggers,
  `cycle N`, `frame N`, and `line N`.

**US-36 [shared] History.** As any user, I want back and forward over my jumps, so that
exploring never loses my place.
- Opening a cycle, step, frame, or palette target pushes history. Back and forward restore the
  view, selection, and scroll position.

**US-37 [shared] Copy for review.** As a reviewer, I want to copy any table or inspector section
as Markdown, so that I can paste evidence into a pull request.
- button "Copy" on every table and section copies the visible rows, including the evidence
  status and reason columns.

**US-38 [shared] Shortcuts.** As any user, I want keyboard shortcuts for view switching, list
navigation, next and previous slow cycle, and inspector focus.

**US-39 [shared] Theme.** As any user, I want light and dark themes with scales that stay
readable in both.

### J12: Scale

**US-40 [rgstats] Large captures stay responsive.** As a platform contributor, I want a capture
from a long interactive session to open and scroll smoothly, so that the tool keeps up with
real recordings.
- A capture with 100,000 cycles and 100,000 frames opens, and its cycle list, frame strip, and
  timeline scroll without frames over budget. Observatory's own capture of this interaction is
  its scaling case.

## 6. Information architecture

```
┌ capture bar: tabs · identity chips · health chips · baseline ─────────────────── palette ┐
├ nav rail ┬ main view ───────────────────────────────────────────────┬ inspector ─────────┤
│ Overview │                                                          ┆ follows selection  │
│ Interact.│   the selected view                                      ┆ resizable, pinnable│
│ Spec     │                                                          ┆                    │
│ Frames   │                                                          ┆                    │
│ Timeline │                                                          ┆                    │
│ Memory   │                                                          ┆                    │
│ Scaling  │                                                          ┆                    │
│ Health   │                                                          ┆                    │
├──────────┴──────────────────────────────────────────────────────────┴────────────────────┤
│ status bar: row counts · family statuses of the current view · query time                │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Capture bar:** one tab per open capture. The baseline is marked with `◆`.
- **Nav rail:** a view is shown dimmed, with its reason, when the capture has no evidence for it
  (for example Frames in a headless capture).
- **Inspector:** shows the detail of whatever is selected (cycle, step, frame, family, list), so
  every view drills down in the same place.

## 7. Wireframes

These are placeholders. They fix the content and hierarchy, not the final visual design. Values
are illustrative.

### W0: Start

Serves US-1 to US-5.

```
┌ Observatory ─────────────────────────────────────────────────────────────────────────────┐
│                                                                                          │
│   [ Open capture… ]  [ Open folder… ]            drop .rgstats files anywhere            │
│                                                                                          │
│   RECENT                                                                                 │
│   ● enter-100.rgstats          nested-hover-grid · enter-100 · headless · ✓ complete     │
│   ● 1790122330-main.rgstats    database-browser · interactive · gpui-wayland · ✓         │
│   ○ bench-out/ (folder)        34 captures                                               │
│   ⚠ old.rgstats                schema 4 is not supported; Observatory reads schema 23    │
│                                                                                          │
│   CAPTURES in bench-out/                          sort: [time ▾] app spec scale health   │
│   file                     app               spec        backend    scale  detail  ✓     │
│   enter-100.rgstats        nested-hover-grid enter-100   headless     100  summary ✓     │
│   enter-1k.rgstats         nested-hover-grid enter-1k    headless    1000  summary ✓     │
│   enter-10k.rgstats        nested-hover-grid enter-10k   headless   10000  summary ⚠     │
│                                            [ Open ]  [ Compare 2 selected ]  [ Scaling ] │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### W1: Overview

Serves Q1, Q2, US-6. Each tile opens the view that explains it.

```
┌ enter-100.rgstats ◆ │ + ─ [headless] [summary] [schema 23] [✓ final] [gaps 0] [isolated] ┐
├──────────┬──────────────────────────────────────────────────────────┬────────────────────┤
│▸Overview │ nested-hover-grid · spec enter-100 · release             │ INSPECTOR          │
│ Interact.│ commit 3d2c7f1 (dirty) · Ryzen 7 9700X ×16 · linux x86_64│                    │
│ Spec     │ benchmark: 2 warmups · 7 samples · scale 100             │ Median cycle       │
│ Frames ░ │                                                          │ 0.53 ms            │
│ Timeline░│ ┌ Outcome ──────┐ ┌ Slowest trigger ┐ ┌ Median cycle ──┐ │ trigger hover-enter│
│ Memory   │ │ 9/9 runs pass │ │ hover-enter     │ │ 0.53 ms        │ │ 7 samples          │
│ Scaling  │ │ 63 steps      │ │ max 0.91 ms     │ │ spread 0.08 ms │ │ family host_cycles │
│ Health   │ └───────────────┘ └─────────────────┘ └────────────────┘ │ status complete    │
│          │ ┌ Frames > 16ms ┐ ┌ Allocs / cycle ─┐ ┌ Skip rate ─────┐ │                    │
│          │ │ —             │ │ 1.2k · 88 KB    │ │ 97%  35 of 36  │ │ [Open Interactions]│
│          │ │ not_recorded  │ │                 │ │ compared       │ │                    │
│          │ └───────────────┘ └─────────────────┘ └────────────────┘ │                    │
├──────────┴──────────────────────────────────────────────────────────┴────────────────────┤
│ 9 runs · 63 steps · 18 cycles │ gpui_* not_recorded: semantic headless draws no frame    │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```
(`░` = a view dimmed because its evidence is not recorded in this capture.)

### W2: Interactions

Serves US-9 to US-12.

```
├──────────┬──────────────────────────────────────────────────────────┬────────────────────┤
│ Overview │ Phase: [measured ▾]   Patch: [all ▾]   Baseline: none    │ CYCLE r4 #12       │
│▸Interact.│ TRIGGERS                                                 │ hover-enter·replace│
│ Spec     │ trigger      patch    n   min   median  max   spread dist│ 0.91 ms            │
│ Frames   │ hover-enter  replace  7  0.47   0.53   0.91   0.08  ▁▆█▂ │ (see W3)           │
│ ...      │ init         mount    9  2.10   2.31   2.60   0.21  ▂█▃  │                    │
│          │                                                          │                    │
│          │ DURATION DISTRIBUTION (hover-enter, log)                 │                    │
│          │  ▁▁▃██▅▂▁      ▁        median ┆ 0.53    max ┆ 0.91      │                    │
│          │                                                          │                    │
│          │ CYCLES  sorted by duration ▾                             │                    │
│          │ run  #   trigger      patch    dur    callback│val│apply │                    │
│          │ s4  12   hover-enter  replace  0.91  ██████████▒▒▒░░░░   │                    │
│          │ s1  12   hover-enter  replace  0.58  ███████▒▒░░░        │                    │
│          │ s6  12   hover-enter  replace  0.53  ██████▒▒░░░         │                    │
```

### W3: Cycle inspector

Serves US-13 to US-18. Shown in the inspector column, or full-width when expanded.

```
┌ CYCLE s4 #12 · hover-enter · replace · measured ─────────────── [Show step ▸ line 14] ─────┐
│ WATERFALL                                            0      0.25     0.5    0.75   0.91 ms │
│ cycle                     0.91 ms  ████████████████████████████████████████████            │
│ ├ roc callback            0.62     ██████████████████████████████                          │
│ │ ├ routing               0.02     █                                                       │
│ │ ├ application_update    0.05       ██                                                    │
│ │ ├ application_render    0.31         ███████████████                                     │
│ │ ├ component_comparison  0.04                        ██                                   │
│ │ ├ platform_lowering     0.17                          ████████                           │
│ │ └ unattributed          0.03                                  ▒                          │
│ ├ validate                0.11                                   █████                     │
│ ├ apply                   0.16                                        ███████              │
│ │ ├ graph apply           0.16                                                             │
│ │ └ gpui apply            —     not_recorded (headless)                                    │
│ └ unattributed            0.02                                                ▒            │
│ Σ parts = 0.91 ms ✓                                                                        │
│                                                                                            │
│ COMPONENT WORK  (recorded)     GRAPH WORK                 ALLOCATIONS by span              │
│ rendered        1              staged       4             span        calls  bytes         │
│ compared       36              removed      4             update         12   1.1 KB       │
│ skipped        35  97%         live      2410             render        840  61 KB         │
│ mounted         0              retained    31             lowering      310  24 KB         │
│ retired         0              validation  52             comparison     20   1.9 KB       │
│ registry visits 3              keyed_*      0 (not keyed) routing         4   0.2 KB       │
│ ancestor inval. 2                                                                          │
│ [▸ by component (E5)]                                                                      │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

### W4: Spec

Serves US-19 to US-21.

```
├──────────┬──────────────────────────────────────────────────────────┬────────────────────┤
│ Overview │ enter-100.scm  ✓ matches spec_hash  Run: [median ▾]      │ STEP line 14       │
│ Interact.│ st  dur   cyc patch│                                     │ hover-enter        │
│▸Spec     │                    │ 1 (test "nested hover grid 100"     │ role operation     │
│ ...      │                    │ 2   (grants (directory "fixture"))  │ pass · 0.53 ms     │
│          │                    │ 3   (benchmark :warmups 2 :samples 7│ 1 cycle · replace  │
│          │  ✓   0.02   0   —  │ 9     (expect-visible (role button …│ staged 4 removed 4 │
│          │  ✓   —      —   —  │12     (mark-metrics)                │                    │
│          │  ✓   0.53   1  repl│14     (hover-enter (role button …)) │ [Open cycle ▸]     │
│          │  ✗   0.01   0   —  │16     (expect-component-work …)     │                    │
│          │      ┆ expected rendered 1, observed 2                   │                    │
│          │      ┆ kind      expected  observed                      │                    │
│          │      ┆ rendered         1         2  ✗                   │                    │
│          │      ┆ skipped         35        34  ✗                   │                    │
```

### W5: Frames

Serves US-22 to US-25.

```
├──────────┬──────────────────────────────────────────────────────────┬────────────────────┤
│▸Frames   │ Budget: [60 Hz ▾]    1,842 frames · 3 over budget        │ FRAME 1207         │
│          │ FRAMES (stacked: layout request · prepaint · paint)      │ layout req 3.1 ms  │
│          │ 16.7┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┃┄┄┄┄┄┄┄┄┄┄│ prepaint   6.0     │
│          │     ▁ ▁▂ ▁▁  ▁▁▁▂ ▁   ▁▁   ▁▁ ▁▁▁▁   ▁▁▁  ▁▁ █  ▁▁▁▁▁    │ paint      9.4     │
│          │ layout solve ░░░ unavailable: solved inside GPUI root    │ = 18.5 ms ✗ budget │
│          │ presentation ░░░ unavailable: GPUI keeps present private │ cause: not recorded│
│          │                                                          │   (E2)             │
│          │ NATIVE WORK (selected frame · mean · max)                │                    │
│          │ kind            renders  created                         │ FRAME WORK         │
│          │ text                412      412                         │ replay share 12%   │
│          │ button              36       36                          │ fresh scene ops 9k │
│          │ virtual item        48       48                          │ cached paint  3    │
│          │ keyed container      1        1                          │                    │
│          │ VIRTUAL LISTS                                            │                    │
│          │ list   visible  materialised  recycled  live             │                    │
│          │ #41        24           26          2     28   ✓         │                    │
│          │ #77        12          400          0    400   ⚠ 33×     │                    │
```

### W6: Timeline

Serves US-26 and Q13. Needs E1 to E4.

```
├──────────┬───────────────────────────────────────────────────────────────────────────────┤
│▸Timeline │ zoom [────●──────]  0 s ──────────────────────────────────────────────── 42 s │
│          │ cycles  click ▮      text_change ▮▮▮▮▮▮      task ▮          click ▮          │
│          │ frames  ||||| ||||||||||||||||||||||||| |||||||||| ||||   |||||||||||||       │
│          │          ↑ frame 1207 over budget ─ caused by cycle 88 (text_change → input 3)│
│          │ lists   #41 ▪ ▪▪▪▪▪▪▪                     #77 ▪▪▪▪▪▪▪▪▪                       │
```

### W7: Scaling

Serves US-29 and US-30.

```
├──────────┬──────────────────────────────────────────────────────────┬────────────────────┤
│▸Scaling  │ Set: enter-100 · enter-1k · enter-10k   A/A: enter-100b  │ GATE ✓             │
│          │ Metric: [callback ▾]                                     │ same app ✓         │
│          │  ms (log)                               ● hover-enter    │ same exe hash ✓    │
│          │  10 ┤                            ●      ┄ linear ref     │ isolated timing ✓  │
│          │   1 ┤              ●         ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│ jobs = 1 ✓         │
│          │ 0.1 ┤   ●     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│ scale check 3/3 ✓  │
│          │     └──100───────1k────────10k── scale (log)             │                    │
│          │ trigger      metric    100→1k  1k→10k  verdict           │                    │
│          │ hover-enter  callback   9.6×   11.8×   ≈ linear          │                    │
│          │ hover-enter  graph      9.9×   31.0×   super-linear ⚠    │                    │
│          │ hover-enter  allocs    10.0×   10.0×   linear            │                    │
```

### W8: Compare

Serves US-31 and US-32. The baseline is applied everywhere. This is the comparability sheet.

```
┌ COMPARABILITY  A: main.rgstats ◆ baseline   B: branch.rgstats ────────────────────────────┐
│ key               A                 B                 ✓                                   │
│ schema_version    22                22                ✓                                   │
│ spec_hash         9f3a…             9f3a…             ✓                                   │
│ backend           semantic-headless semantic-headless ✓                                   │
│ cpu_model         Ryzen 7 9700X     Ryzen 7 9700X     ✓                                   │
│ timing_quality    isolated          partial-contended ✗  B was measured under contention  │
│ ⇒ incomparable: no deltas are shown.                               [Open anyway as tabs]  │
└───────────────────────────────────────────────────────────────────────────────────────────┘
  with a baseline applied, W2 gains:  median  Δ        ratio  noise
                                      0.49   −0.04 ms  0.92×  within A/A ±0.05
```

### W9: Health

Serves US-8.

```
├──────────┬───────────────────────────────────────────────────────────────────────────────┤
│▸Health   │ VERDICT  complete · every required family finalised without recorded loss     │
│          │ MEASUREMENT FAMILIES                                                          │
│          │ family                 detail   status        rows  omitted  reason           │
│          │ host_cycles            summary  complete        18        0  finalized …      │
│          │ roc_work_spans         summary  complete        63        0  every recorded … │
│          │ gpui_frame_spans       summary  not_recorded     0        0  headless draws … │
│          │ gpui_presentation      summary  unavailable      0        0  GPUI keeps …     │
│          │ RECORDING GAPS   none                                                         │
│          │ RECORDER HEALTH  tx 41 · queue hw 12 · 160 KB · writer ok · limit ok          │
│          │ IDENTITY         38 keys  [expand]   unavailable: gpu_timing, …               │
```

### W10: Command palette

Serves US-35 and US-38.

```
            ┌────────────────────────────────────────────────┐
            │ > hov                                          │
            │   Trigger  hover-enter             Interactions│
            │   Trigger  hover-exit              Interactions│
            │   Step     line 14 hover-enter          Spec   │
            │   Command  Set as baseline               ⌘B    │
            └────────────────────────────────────────────────┘
```

## 8. Evidence requests

Stories marked with **E*n*** need evidence the recorder must provide. Each request is added by
the component that owns the work, only once production code populates it, with a schema
version bump (see `AGENTS.md`). Until then, the corresponding UI shows "not recorded".

| # | Request | Needed by | Privacy |
|---|---|---|---|
| E1 | A shared monotonic timestamp (start, end) on `cycles`, `gpui_frames`, and `virtual_list_frames` | US-26 Timeline, US-33 | Process-relative clock only |
| E2 | Frame-to-cycle linkage recorded by the owner that knows it, as a link table so a frame the event loop coalesced several cycles into names each, and a frame that drew no new cycle names none | US-22, US-26 | None |
| E3 | `virtual_list_frames` linked to the frame (or cycle) that produced the pass | US-25, US-26 | None |
| E4 | Target of an interactive cycle: node kind plus a stable, non-textual node identity | US-12, US-26 | Labels and text are application text and stay excluded |
| E5 | Component work attributed per component instance by a stable, non-textual identity | US-18 | Component keys may derive from application state; identity must be opaque |
| E6 | Interactive canvas pointer drags recorded as cycles, as other interactive events are | US-9, US-26 | None |
| E7 | A capture identity (`capture_id`) and a documented live-read contract: which tables a reader may trust before `final_state` | US-33, US-34 | Random identifier, no machine identity |

E1, E2, and E7 are the same requests the `.rocobs` plan makes, so the conventions should match.

## 9. Platform capabilities the ideal relies on

The numbering follows the Roc Observatory viewer plan, so both applications share one
vocabulary. **Both** means both viewers need it.

| # | Capability | Stories | Used by |
|---|---|---|---|
| P1 | Virtual list with a row provider, programmatic scroll-to, and visible-range events | US-2, US-10, US-19, US-36, US-40 | Both |
| P2 | Rich text runs: several styles in one line | US-19, US-20 | Both |
| P3 | Keyboard events, window shortcuts, and focus control | US-35, US-38 | Both |
| P4 | Tooltips and popovers anchored to any element | US-7, US-11, US-26 | Both |
| P5 | Resizable split panes and tabs | §6 shell, US-1 | Both |
| P6 | Canvas text, hover movement, wheel and zoom | US-11, US-22, US-26, US-29 | Both |
| P7 | SQLite for large captures, opened in place, with bound parameters, paging, `ATTACH`, cancellation, and WAL reading | US-10, US-32, US-33, US-40 | Both |
| P8 | Watching granted files for change | US-33, US-34 | Both |
| P9 | Single-file chooser with type filter, file drop, and recent documents | US-1, US-3, US-4 | Both |
| P10 | Content hash of file bytes | US-19 | Both |
| P13 | Task cancellation and supersede | US-10, US-36 | Both |
| P14 | Theme query (light/dark) | US-39 | Both |

## 10. Specifications and scaling case

- Specifications live in `examples/observatory/specs/` and drive the application through the
  locators named in §5.
- Fixture captures are produced at test time by running real specifications of existing
  examples through `scripts/run_specs.py`, and by recording a real interactive session. They
  are not committed.
- The scaling case is opening and navigating a long interactive-session capture at increasing
  cycle and frame counts (10k and 100k), through the ordinary Open, Interactions, and Frames
  paths.

## 11. Iterations

Each iteration ends with a working application and complete features (ABI, host behaviour,
locators, counters, specifications, a scaling case, and documentation).

| Iteration | Delivers | Stories |
|---|---|---|
| I1 | Skeleton: folder open, capture list, schema gate, Health, Overview, Spec results table. README, specs, fixture generator, scaling case | US-2, US-5, US-6, US-7, US-8, US-9 (table), US-21 |
| I2 | Interactions and cycle inspector, with canvas bars | US-10, US-13 to US-17, US-27, US-28 |
| I3 | P9 file open, recents, and drop | US-1, US-3, US-4 |
| I4 | P5 split panes and P4 popovers → the §6 shell | US-7 (hover), §6 |
| I5 | P6 canvas text and hover → distributions, Frames, Scaling | US-11, US-22 to US-25, US-29, US-30 |
| I6 | P7 SQLite → Compare and large captures | US-31, US-32, US-40 |
| I7 | P3 keyboard, palette, and history; P2 rich text → annotated Spec | US-19, US-20, US-35 to US-38 |
| I8 | P8 watching and E7 → live session | US-33, US-34 |
| I9 | E1 to E6 → Timeline and attribution | US-12, US-18, US-26 |
