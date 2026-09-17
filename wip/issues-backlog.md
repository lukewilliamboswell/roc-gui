# Issues backlog

Gaps between the documented ideal state in `docs/` and the repository as it is.
Each entry names its effect and the change that closes it. Remove an entry when
the change lands; do not soften the docs to match the gap.

## Resource broker and confinement foundation

- [ ] **The linked process is not an untrusted-application boundary.** Implement
  Linux application-process confinement and an out-of-process trusted broker.
  Define the compiler, runtime, native-library and packaging trust base; prevent
  syscall, inherited-descriptor, dynamic-library, IPC and dependency escape
  routes; and verify denial outside grants. The audited starting point and
  platform matrix are in `wip/resource-access-inventory.md`.
- [ ] **Trusted identity, access review, and revocation are absent.** Define
  stable publisher/package identity, remembered-grant storage and migration,
  expiry and a protected App access surface. Files now carry root/child ancestry
  and a host-owned revocation linearization rule; extend that rule to other
  resources and certify cross-process queued/running races and already-returned
  byte policy under confinement.
- [ ] **Trusted file workflows remain incomplete.** Open Project is presented by
  the operating system on both hosts: the production XDG Desktop Portal on Linux
  Wayland and the window-owned native directory panel on macOS. Both record
  session/source/parent lineage, and `--host-cap-dir` remains development
  provisioning. The macOS panel is a native chooser, not a sandbox powerbox: it
  grants no authority the unsandboxed process does not already hold, so it is
  honest consent but not enforcement until the macOS sandbox work below lands.
  Add Open
  Document's smallest single-file grant, persistent grants, revocation, edit
  grants, and brokered atomic Save As with overwrite, race, disk-full, cleanup,
  cancellation and retry semantics.
- [ ] **Portal parenting and protected consent need external certification.**
  GPUI 0.2.2 does not expose an xdg-foreign Wayland surface handle to this host,
  so the portal request cannot yet name its parent window. Export that handle,
  attribute focus, and certify compositor placement, protected portal identity,
  cancellation and accessibility on a packaged confined application. Headless
  semantic specifications cannot supply this evidence.
- [ ] **Platform enforcement remains unverified.** Implement and test the
  complete confinement/broker boundary on Linux Wayland. Define and verify
  macOS sandbox, entitlement, trusted-panel, signing and notarization behavior
  before adding that target; other platforms require equivalent evidence.
- [ ] **Absent native effects have not been proven unreachable.** Audit secure
  randomness, URI opening, webviews, microphone/camera/screen capture,
  drag-and-drop/sharing, file clipboard, global input/automation, accessibility,
  native extensions, IPC/listening sockets, inherited descriptors and linked
  dependencies. Add no public API until its complete broker policy and tests
  land.

## Device Configurator follow-on features

- [ ] Add hot-plug notifications and reconnect policy to the host-owned HID
  connection lifecycle, preserving stale-completion suppression in the app.
- [ ] Add persistent named mapping profiles and per-control remapping once the
  protocol represents those fields; retain atomic acknowledged apply.
- [ ] Add a signed, integrity-checked firmware-update protocol with explicit
  cancellable and non-cancellable phases before exposing firmware controls.
- [ ] Validate physical HID behavior on macOS and Windows and add target-specific
  `hidapi` backends before advertising those hosts as supported.

## Terminal workspace follow-on features

- [ ] Propagate live pane dimensions through the layout owner to
  `Process.Pty.resize!` and specify the resulting PTY size without exposing a
  fixed-size product control.
- [ ] Add ANSI/VT cell parsing, wide and combining glyph layout, selection,
  clipboard policy, and URL recognition on top of the ordered PTY byte stream.
- [ ] Add tabs, nested split panes, focus navigation, pane zoom, and persisted
  workspace layouts using the existing mounted graph and event route.
- [ ] Add user-configurable shell-profile grants without exposing executable or
  environment selection as ambient application authority.

## Element appearance

- [ ] **No letter spacing.** A small muted caption above a large numeral is
  conventionally tracked out, and tracking is what distinguishes an eyebrow
  label from ordinary body text once family is unavailable. `counter`'s per-card
  captions are plain small grey text instead. GPUI 0.2.2 has no letter-spacing
  concept at all: neither `TextStyle` nor `TextStyleRefinement` carries one, and
  the shaper takes none, so this needs an upstream field before a
  `Gui.Style` letter-spacing field can mean anything.
- [ ] **A border is one colour on all four sides.** Per-side widths have
  landed, and `terminal-workspace` now draws one hairline on the edge that faces
  the next region instead of boxing every region and holding the boxes apart
  with a 1-point seam. Per-side colour is not expressible: GPUI 0.2.2's `Style`
  carries `border_widths` as `Edges` but a single `border_color`, so a side
  cannot have a colour of its own without an upstream change.
- [ ] **A large SVG is rasterized at its own size and then never painted.**
  `gpui` 0.2.2 decodes an SVG through
  `SvgRenderer::render_pixmap(&bytes, SvgSize::ScaleFactor(1.0))`
  (`src/platform.rs`, `ImageFormat::Svg`), so the raster is the file's intrinsic
  size and the element's box is never an input: `SvgSize::Size(_)` exists but the
  image-asset path never uses it. `image-library`'s 8000x6000 fixtures therefore
  produce a 48-megapixel frame that nothing paints, while the 24x24 glyph in
  `icons/unreadable.svg` paints correctly — proved by
  `examples/image-library/specs/window-unreadable.scm` against a gallery whose
  thumbnails are blank. The element geometry is right: the same window run
  measures each thumbnail at exactly 88x88 and the viewer image on screen. This
  needs `SvgSize::Size` at the laid-out box upstream, or a host-side SVG
  rasterizer, and should not be worked around by shrinking the fixtures, which
  are deliberately larger than any box they are put in.

## Trust: measurements that can mislead a decision

- [ ] **Memoization measurements do not isolate every ownership or equality
  cost.** The textarea append and same-length late-edit ladders exercise large
  edited children with explicit equality and without memoization. Equal,
  independently allocated inputs remain a separate comparison case. Live
  snapshot retention and copying attributable specifically to lost uniqueness
  remain unmeasured: allocator requests are not retained bytes or a copy counter.
  Measure these through their production owners before making those claims.

- [ ] **General GPUI entity lifecycle counts are not captured.** The virtual
  list reports viewport-owned entity materialisation, retention, and recycling,
  but eager native views do not yet emit general materialised, rebound, and
  retired entity counts. Direct native identity tests prove reuse semantics;
  schema-11 component and mounted-node counts do not measure native entity
  construction or rebinding. Add owner-populated counters and then their schema,
  queries, and production-window assertions together, without inferring them
  from graph retention or a timer.

- [ ] **Window benchmark warmup and sample orchestration.** Real-window
  hover-grid runs can record schema-14 captures containing native frames and
  live task completions. The specification runner still runs a single window
  lifecycle: `spec::check_runner` refuses benchmark steps there. Add production
  window orchestration for warmups, samples, iterations, and per-sample reset,
  then route those captures through the existing scaling and A/A reports.

## Performance findings from the suite

Defects in the platform or host that the benchmark suite has exposed. Each
names the evidence so a fix can be verified against the same case.

- [ ] **Explain development-backend local callback timing growth.** Final
  schema-15 same-executable A/A row-boundary runs preserve one boundary render,
  one registry lookup, one ancestor invalidation, and three getter/one setter
  calls for unmemoized local edits at 100, 1,000, and 10,000 rows. The first
  run's callback medians nevertheless rise from 62.35 to 107.50 to 282.14 us;
  its repeat records 65.93, 108.65, and 281.35 us. Routing, application update,
  application render, and platform lowering owner spans all increase. Render
  allocation requests remain 9,880 bytes; update requests are 5,440, 5,656,
  and 5,872 bytes. Profile the remaining work before attributing the increase
  to traversal, allocation, cache behavior, or any other unmeasured mechanism.
  Bounded render/projection counts do not establish constant callback time.
  Preserve the explicit development-backend qualification and compare only
  compatible builds. Evidence: `target/adapter-cps-production/report.md`.

- [ ] **Audit native layout and arbitrary application recursion separately.**
  Host entity lifecycle walks are iterative. GPUI's element layout/paint
  calls, application render functions, and arbitrary callback closures have
  separate stack behavior. Measure and constrain those owners before claiming
  unrestricted native or application depth. A headless structural-depth result
  does not prove native layout stack safety.

- [ ] **Reuse intrinsic and flexible native container subtrees.** Fixed-size
  non-root rows, columns, and panels can cache their native subtree because
  their exact outer dimensions do not require measuring children. Intrinsic
  and flexible containers still build their contents for layout. Extend reuse
  with a layout contract that preserves content sizing, flex distribution,
  inherited styles, clipping, input, and descendant invalidation. Verify the
  production native render and element-construction counters independently;
  do not force application geometry merely to make a cache eligible.

- [ ] **Exact native render contracts need native invalidation attribution.**
  Roc patches supply the changed and retained frontier, and production native
  counters can check patch-derived expectations in controlled GPUI tests.
  Arbitrary interactive frames also include focus, pointer styling, geometry,
  inherited styles, and GPUI refreshes. GPUI 0.2.2 keeps its dirty-view set and
  refreshing flag private, so the host cannot classify every native render
  cause. Expose those causes before treating every render outside a Roc patch
  as a production invariant violation. Keep actual counters always available;
  neither silently exempt unexplained work nor claim an unconditional contract
  from the controlled tests.

- [ ] **Reduce GPUI scene reuse and reconstruction work as the scene grows.**
  The schema-14 native hover baseline recorded 210 completed frames and exactly
  100 enter, 100 exit, and 100 task-completion cycles. Host-owned mean frame
  spans were 8.041 ms layout request, 21.876 ms prepaint, and 49.403 ms paint;
  steady frames constructed 10,000 boundary wrappers. Fixed-container subtree
  reuse addresses wrapper construction, but scene replay and reconstruction
  can still traverse retained scene data. Profile the changed production path
  and compare owner spans and native counts before attributing remaining cost.
  These timings are report-only; they do not measure retained memory or bytes
  copied, and the baseline does not establish post-change work.

  Close this gap by retaining native subtree records across frames, not merely
  suppressing `NodeView::render`. The production owners are
  `vendor/gpui/src/view.rs` (cached subtree lifetime), `window.rs` (frame records,
  replay ranges, transactional prepaint, hitboxes and listener ownership),
  `scene.rs` (primitive insertion, overlap order and batching),
  `key_dispatch.rs`, `tab_stop.rs`, `text_system/line_layout.rs`, and the Blade,
  Metal and DirectX renderers. `crates/host/src/lib.rs` supplies the mounted
  change frontier and descendant notifications; it must not build a second
  scene or event implementation.

  A candidate design uses persistent subtree segments with stable handles and
  ordered child references. Retain scene commands, interaction records, focus
  paths, element state and text resources under the same segment lifetime;
  replace only changed segments and their ancestor links. Preserve stacking and
  overlap order, clipping, inherited text, focus/tab order, moved children,
  handler revisions, modal input policy and removal. Mutable callback ownership
  and resource retirement must remain valid while prior frames still reference
  a segment. Aborted prepaint transactions must publish nothing. Flattening
  segments into the existing full-frame vectors at presentation would only move
  the global work, so renderer submission and retained buffers or damage-based
  presentation belong to the design, with each platform's buffer-age rules
  verified separately.

  Add production-owner deterministic counts before judging this change:
  scene operations replayed, primitive insertions, hitbox slots copied, listener
  slots transferred, dispatch nodes reconstructed, tab operations replayed and
  element-state entries visited. Range lengths permit one increment per replay
  batch; distinguish slots visited from callbacks invoked and operations replayed
  from primitives actually emitted. These counts are unmeasured and unavailable
  until their owners populate them; do not add empty schema columns or derive
  them from render counts. Include a schema increment and reporting tests when
  measurement lands.

  Acceptance uses the actual hover-grid application and mounted patches at
  100, 1,000 and 10,000 cells, with viewport, tree depth and affected-cell count
  controlled. Once initial construction is excluded, one local hover update or
  delayed completion must not visit, copy, rebuild or submit unrelated retained
  records in proportion to total cell count. Vary depth separately and account
  for the changed ancestor path. Include same-color updates, idle frames,
  reorder/removal, clipping/resize, overlapping surfaces, focus, window exit,
  stale callbacks and transaction retries. Gate deterministic owner work and
  semantic results; report timing and A/A noise separately. A reduced wrapper
  count alone does not close this entry.

- [ ] **Dense native hover still traverses GPUI input structures globally.**
  A user-driven 10,000-button hover-grid profile, excluding its first two seconds,
  recorded 4,456 user-CPU samples: about 19% in GPUI mouse-listener wrappers,
  4.5% in frame hit testing, and 5% in bounds-tree insertion. This exploratory
  run overlapped other work and had incomplete Rust stack unwinding; these are
  exclusive sample shares, not latency measurements or caller attribution.
  GPUI 0.2.2 dispatch traverses the frame listener list in capture and bubble
  order, and hit testing scans hitboxes. A spatial hit-test index alone would
  leave listener traversal. Profile native input separately from frame work,
  preserving hover exit, capture, stacking, clipping, drag, and removal semantics
  before changing dispatch further. Use retained ordered interaction segments
  and a spatial candidate index together; separately retain capture/outside
  listeners and the previously hovered path so exit delivery survives moving
  away or leaving the window. A native mouse event must visit only relevant
  candidates, ancestor routes and explicitly global handlers rather than every
  unrelated control. Owner counts of hitboxes examined and listeners actually
  invoked must follow real early exits and propagation stops; they remain
  unavailable until instrumented. Apply the controlled-dimension scaling and
  lifecycle acceptance cases in the scene-retention entry above.

- [ ] **Timer waits occupy the generic task workers and extend hover trails under load.**
  The hover-grid application schedules a 200 ms Timer wait per exiting cell.
  Those waits start inside the existing 4–16 blocking workers; additional jobs
  wait in an unbounded queue. Reset latency includes queue delay as well as the
  requested interval, and queued closures retain resources. The 32-cell burst
  case exposes this through production tasks. Add deadline-aware nonblocking
  timer delivery or equivalent bounded scheduling without global redraws,
  preserve boundary ownership and stale-completion suppression, and measure
  queue depth and delay at their production owner before making latency claims.

- [ ] **Generated Roc API pages omit record-field documentation.** Running
  `roc docs platform/main.roc` renders the `Elem.TranslateConfig` type comment
  and signature but omits the doc comments on `key`, `get`, `set`, `on_delegate`,
  and `memo`. The type-level documentation includes the essential contracts so
  readers can use the generated reference. Track the compiler documentation
  generator fix and verify the field descriptions in its HTML output.

- [ ] **Resolve the default LLVM backend's CPS runtime corruption.** The
  temporary workaround is to add `--opt=dev` to the `roc build` commands in
  the guides and example READMEs. The specification driver defaults to this
  backend while the compiler issue is open. This is not a platform requirement;
  remove the driver override after verifying the compiler fix.
  Selected compiler builds of the counter and review-queue succeed with the
  default LLVM backend, but those executables expose incorrect initial state
  and callback reference-count failures. Identical production source built
  with `--opt=dev` passes all 17 core semantic specifications and all 27 flat
  and nested hover specifications. The failure also reproduces with an
  exact-commit Debug compiler and local compiler revision `ee6e57c7`. The
  successful development-backend evidence does not establish default-backend
  acceptance. Minimize the compiler-dependent ownership or layout failure,
  then rebuild and verify both modes before removing this blocker.

- [ ] **A guarded match over a local tag value segfaults the built
  application.** Reaching for a chosen-row marker in `examples/music-player`,
  this shape crashed the built executable with SIGSEGV in
  `specs/stale-load.scm`, `specs/window-decode-error.scm` and
  `specs/window-identity.scm`:

  ----
  match state.chosen {
      Nothing => sounding
      At(index) => match sounding {
          Sounding(active) if active == index => sounding
          Held(active) if active == index => sounding
          _ => Waiting(index)
      }
  }
  ----

  The same function rewritten to compare an index instead of re-matching the
  local tag value passes all nine cases, which is what the example now does. The
  shape extracted into a module and exercised with `roc test` does **not**
  reproduce it, so the trigger needs the full application build and is not yet
  minimized. Minimize it against the pinned compiler, report it, and update the
  pin when fixed.

- [ ] **An unannotated helper that reads a field of its own result segfaults
  `roc check`.** Reaching for undo and redo that reconcile a stale selection in
  `examples/animation-studio`, this shape crashed the compiler itself — not the
  built application — with SIGSEGV at fault address `0x3f8`, with no diagnostic
  and no stack trace:

  ----
  restore = |state, document, status| {
      settled = apply_frame({ ..state, document, drag: Idle, status })
      keeps = match settled.selected {
          None => False
          Some(id) => match settled.document.shapes.find_first(|shape| shape.id == id) {
              Ok(_) => True
              Err(_) => False
          }
      }
      if keeps settled else { ..settled, selected: None }
  }
  ----

  Adding the annotation `restore : State, Document, Str -> State` makes it
  compile, and nothing else about the body has to change, so the trigger is
  inference over a helper whose parameter and result types are only pinned down
  by another unannotated helper (`apply_frame`) in the same module block.
  Reordering the two definitions makes no difference. The example carries the
  annotation. Minimize it against the pinned compiler, report it, and update the
  pin when fixed.

- [ ] **Persistent-index maintenance retains a high allocation constant.**
  Bounded route-ID chunks removed the superlinear ownership-list allocation
  term. Compact leaves and element updates further reduced the constant: a
  10k memoized ancestor selection makes 399,333 measured allocation calls,
  and the existing 100k full-root sparse update makes 3,008,082.
  Investigate indexed maintenance and reference-count
  overhead without weakening revision checks or atomic graph/session acceptance.
  See PR #23 for the measured optimization history and rejected follow-ups.
  Timing alone must not gate correctness.

- [ ] **Investigate remaining full-root scaling after keyed component retention.**
  Historical serial schema-11 captures passed all four sparse-update scales
  and A/A repeats with the compiler/backend used for that checkpoint. The
  10k to 100k median grew from 60.863 ms to 902.451 ms; callback, validation,
  and graph-apply means grew
  14.1x, 16.6x, and 14.3x, respectively. Marked Roc allocation bytes grew
  10.8x. These owner measurements do not establish the cause of time growth.
  Investigate without weakening tree integrity or exact patch counters.
  The pre-component production 100,000-row sparse-update case showed superlinear
  work after dense validation, host-owned child streaming, and consolidation of mounted node
  and parent storage. In a serial same-executable run, 10,000 to 100,000 rows
  grew from 9.47 ms to 139 ms overall. Roc callback work grew 11.4x, validation
  19.0x, and graph apply 20.2x; both lifecycle and measured-span allocated
  bytes grew 10.0x. Further work must preserve the generic tree-integrity
  checks and exact patch counters. The full-root rebuild itself is intentional
  application semantics, with row boundaries providing the local-update
  alternative. These numbers are a historical baseline, not evidence for the
  final schema-15 implementation. Continue using serial same-executable captures
  with the pinned compiler, explicit backend, and schema-15 owner counters.
  Do not compare timings across the historical LLVM and development-backend
  checkpoints. Separate application keyed lookup, Roc comparison and rendering, fresh/frontier validation, and native
  materialisation before assigning the remaining growth to an owner.

- [ ] **Measure native text shaping and deep layout separately from headless work.**
  Text and tree-shape semantic cases measure construction, callback work,
  allocations, patch sizes, and lifecycle behavior. Schema-15 projection
  counters and reduced-stack tree cases additionally verify composed state
  adaptation, deep ownership, task resolution, veto, and teardown. These are
  useful headless measurements; they do not measure GPUI text shaping,
  wrapping, layout, or paint. Historical headless captures showed under 15%
  timing difference between long and short messages at 10,000 rows and no
  observed depth effect in that workload. Those observations do not establish
  native text or depth costs. Add controlled production-window scale ladders
  for text length, width, wrapping, and tree depth, and report owner frame spans
  and native-work counts. Isolate text shaping with a production-owner
  measurement before attributing a whole layout or paint span to shaping.

## Runner: test what we fly

- [ ] **Native frame focus work still scans unaffected controls.**
  `Runtime::render` walks focus handles and computes the graph's focus order on
  focused frames. Deleted-focus and canvas-drag recovery also reverse-search
  native identities. These preexisting paths are separate from graph patch
  work, so bounded component renders and validation visits do not establish
  end-to-end work proportional to changed nodes. Index focus/identity recovery
  and update it from accepted graph deltas, while preserving dialog focus and
  native interaction behavior through production window specifications.

- [ ] **A control that reorders under the finger can hand its press to its
  neighbour.** Element identity is a path of sibling keys, and a node with no
  name of its own — `Elem.text`, and any container an application left unnamed
  — is keyed by its position. If such a node is pressed and its siblings are
  reordered or one before it is removed in the same patch, the identity that
  was pressed now belongs to a different node, and the release completes on
  that one. Explicit keyed components establish a stronger scoped identity,
  but they do not grant arbitrary reparenting: named controls retain identity
  only while their structural ancestor scope survives. Keep this gap for
  anonymous positional control ancestry until a production pointer regression
  proves the required behavior. Do not treat named component reorder coverage
  as proof that every unnamed layout path is safe.

- [ ] **Complete native pointer routing in window specifications.** The local
  GPUI patch exposes `DispatchEventResult`, enabling `hover-enter` and
  `hover-exit` to inject mouse-move events into the real GPUI window. Click
  still uses the production handler after geometry validation, and scroll
  writes the production scroll handle. Migrate those commands to native
  button and wheel events to exercise dispatch order, unrelated occlusion,
  press/release continuity, and wheel routing. This seam does not test
  operating-system pointer delivery or compositor sampling.
- [ ] **A window specification cannot run while the screen is locked.** A
  locked macOS session presents no frame, so every window case reaches
  `driver-started` and waits for one that never arrives until the watchdog
  fires. The watchdog now names the cause rather than reporting only a
  deadline, which is the difference between an environmental note and an
  apparent defect in the host, but the constraint stands: window evidence needs
  an unlocked session. This is why continuous integration needs the headless
  compositor lane below rather than a desktop session.

- [ ] **Shared steps the window runner does not implement.** `drag`,
  `replace-text`, `submit`, `revoke-file-grants`, and the owner counter
  assertions are still classified semantic-only because the window runner
  refuses them, not because they would be dishonest there.

  The value and ordering assertions have since landed and are no longer on this
  list. They cost almost nothing, because each is answered from the mounted
  graph alone: `runner::graph_claim` now holds the only implementation and both
  runners call it, so the five words cannot come to mean two things. The four
  that remain are each a different problem rather than four of the same one.
  `drag` and `submit` want a pointer and a submit route the window runner
  reaches only by simulation, which is the entry above; `replace-text` sets a
  value directly, which in a window would bypass the editing path `type`
  exists to exercise, so it needs a decision about whether that is worth
  offering at all. `revoke-file-grants` and the owner counters read
  process-global state that is already reachable from the window runner — they
  are held back only by the per-counter plumbing, and are the cheapest next
  step.

  `clipboard-text` and `await-ticks` have since landed in the window runner and
  are no longer on this list. They are worth reading before the next one is
  attempted, because each needed a different answer than settling: a clipboard
  watcher rearms its read inside the completion that delivers the last one, so
  one task is outstanding at every instant and quiescence never arrives, and
  `await-ticks` therefore counts timer *fires* rather than completions, since a
  fire can only be one that started after the step did.
- [ ] **CI compositor.** Benchmark jobs run the real Wayland backend under a
  headless compositor such as sway or cage. For Sway this requires a headless
  wlroots output, software rendering on workers without a GPU, and pointer
  movement plus press/release over its IPC or virtual-pointer protocol. The job
  must prove that GPUI receives the real Wayland event before benchmark captures
  are accepted; merely opening a window is insufficient.
- [ ] **Demote the headless runner to smoke.** Remove benchmark policy from it
  and make the scaling and compare views refuse `semantic-headless` captures.
  Strictly after window sample orchestration and compositor verification:
  the automated benchmark matrix uses `semantic-headless`, while individual
  window captures already measure native work. Preserve the explicit backend
  distinction until the sampled native matrix replaces it.

- [ ] **Capture the window, not the screen region.** `screencapture -R` takes a
  screen rectangle, so anything drawn over the window lands in the evidence; a
  1280x800 window on a display with the dock visible photographs the dock. A
  window-targeted capture (`screencapture -l<windowid>`, which reads the
  window's own contents) would be immune, at the cost of cropping in process
  from the returned image rather than in the request. The `image` crate is
  already a dependency; the missing piece is the window id, which GPUI does not
  expose and which would need the pid-to-window mapping the capture currently
  avoids needing.
- [ ] **Wayland window specifications in continuous integration.** The window
  runner is platform-neutral and `grim` is wired for wlroots, but no Linux
  runner has a compositor. This needs the headless lane (`sway --headless`,
  `WLR_BACKENDS=headless`, software rendering) described above.
- [ ] **Golden-image comparison.** Window specifications photograph state but
  never compare images. Comparison needs a storage, review, and update story of
  its own, and should not be bolted onto the capture step.
- [ ] **Multi-display screenshots.** `gpui` 0.2.2 hard-zeroes the macOS display
  origin (`platform/mac/display.rs`) and computes window bounds relative to the
  window's own `NSScreen`, so a window on a secondary display has no recoverable
  global coordinates. Capture reports `unavailable` rather than guessing.

## Release infrastructure

- [x] **Native macOS GPUI smoke shutdown.** The real-window smoke no longer
  blocks: it renders and quits in ~2.3 s across repeated runs on Apple Silicon.
  A block is now a failure inside the host itself rather than only in the driver
  — `crates/host/src/watchdog.rs` arms a native thread before `Application::run`
  that reports the last startup milestone reached (`app-run-entered`,
  `window-opened`, `first-render`, `driver-started`) and exits 101 when the
  deadline passes.
- [ ] **Adopt roc-gui-owned content-addressed releases.** Run the dependency and
  host producer workflows from reviewed repository revisions, publish their
  attested archives, and replace the bootstrap `roc-signals` entries in
  `dependencies.lock.json` with the exact roc-gui release identities before the
  first platform release.

## Input and accessibility

- [ ] **File Explorer writable powerbox and desktop integration.** The read-only
  explorer navigates capability-scoped child folders, preserves back/forward
  history, selects files and folders, reports typed failures, and virtualizes a
  realistic directory. Add a separately approved writable-directory grant and
  direct-child create, rename, copy, move, trash, and restore operations with
  collision policy, partial-result recovery, cancellation, and undo. Add tabs,
  split views, multi-selection, drag-and-drop, clipboard file operations,
  previews, metadata, operating-system open/reveal, watching, and durable grant
  restoration only as complete production slices.
  Replace development `--host-cap-dir` provisioning with trusted native/portal
  Open Project selection for interactive use, record grant ancestry, define a
  revocation linearization point for roots and derived children, and verify
  denial outside the grant and revocation during queued work through the real
  GPUI/trusted-chooser boundary.

- [ ] **Music library metadata, persistence, and media integration.** The music
  player foundation provides explicit folder/output capabilities, Rodio and
  Symphonia decoding, a bounded playback state machine, queue navigation,
  seeking, stale-load suppression, corrupt-media isolation, and a virtualized
  ordinary-use library. Add metadata and artwork extraction, durable roots and
  playlists, filesystem reconciliation, volume and repeat policy, automatic
  end-of-track queue advancement, device-loss recovery, and operating-system
  media controls as complete production slices.

- [ ] **Animation Studio project assets and export.** The editor proves native
  retained vector painting, captured direct manipulation, state-owned undo/redo,
  position keyframes, scrubbing, and cancellable playback. Add capability-scoped
  project save/open, image assets, text, grouping, easing, and deterministic
  frame-sequence export with cancellation before presenting it as a complete
  presentation authoring tool.

- [ ] **Clipboard image formats, durable pins, and global activation.** The
  clipboard-history slice provides explicitly granted, bounded text capture,
  privacy exclusion, restore, cancellation, stale suppression, virtualization,
  and content-free semantic evidence. Add bounded image representations,
  encrypted durable pinned entries, compositor-level change notifications, and
  a globally activated overlay with focus restoration as complete production
  slices before presenting it as a full desktop clipboard manager.

- [ ] **Redis mutation, authentication, and cluster operation.** The Redis
  Explorer foundation exercises an exact-endpoint TCP grant, `roc-redis`,
  bounded incremental SCAN, native type and TTL discovery, and read-only
  inspection for strings, lists, sets, hashes, and sorted sets. Add credential
  capabilities, database selection, cluster redirection policy, optimistic
  mutation with server confirmation, destructive confirmation, expiry edits,
  reconnection, and cancellation as complete slices before presenting it as a
  general Redis administration tool. Credentials must never enter captures or
  ordinary persisted application state.

- [ ] **Broker trusted TCP destinations and revocation.** Numeric exact-endpoint
  provisioning deliberately performs no DNS and serves development and
  automation. Add named user-approved destinations, revocation that closes
  owned streams, and lifecycle evidence through a trusted connection broker
  before applications present a general-purpose Connect UI.

- [ ] **SQLite write transactions and parameters.** The database capability is
  deliberately read-only and executes one statement without bindings. Add a
  separately granted read-write capability, typed parameters, cancellation,
  transactions, paging, editable grids, and export with lifecycle and resource
  counters before presenting the example as a general database administration
  tool.

- [ ] **System Monitor charts and export.** The system-monitor slice has a real
  capability-scoped `sysinfo` sampler, explicit unavailable values, bounded
  history, sorting/filtering/selection, and a virtualized process table. Add
  canvas time-series charts and a separately granted privacy-safe export whose
  schema excludes process names and IDs before offering session export.
- [ ] **System Monitor platform breadth.** Validate the sampler and unavailable
  classifications on macOS and Windows, and add per-disk/per-interface identity
  only with explicit privacy policy and deterministic evidence.

- [ ] **Image decode status is not represented in the mounted graph.** GPUI's
  image asset decoder owns asynchronous success and failure after mounting, but
  does not expose that state to the host element. Add an owner callback that
  records decoded dimensions/frames or a content-free failure category and
  renders a semantic per-image fallback; do not duplicate GPUI's decoder in the
  semantic runner.
- [ ] **Image-library trusted Open and capability lineage.** Development and
  automation provisioning enters the ordinary grant registry, but it is not
  trusted chooser consent. Add a platform-owned Open broker with ancestry and
  revocation semantics before describing interactive folder selection as a
  user grant.
- [ ] **Image-library cancellation and decoded-cache ownership.** Folder scans
  suppress stale task completions, but bounded Files reads do not yet expose
  cooperative cancellation and GPUI does not expose decoded-byte eviction.
  Add those production seams and owner counters before retaining much larger
  raster collections.
- [ ] **Image-library metadata and editing breadth.** Add EXIF orientation,
  color-profile and animation metadata plus production zoom, pan, rotate, crop,
  undo and slideshow primitives. Do not infer these values from filenames or
  add controls that bypass `ImageProps`.
- [ ] **Image-library export broker.** Add a trusted Save/Export broker with a
  separately selected writable grant, collision policy and revocation. The
  existing development directory provision is read-only and must not be used
  as implicit export authority.

- [ ] **Textarea selection, IME composition, and clipboard commands.** The
  production textarea accepts ordinary character, Enter, and Backspace input
  and routes complete controlled values through Roc. Close the desktop-editor
  gap with GPUI `EntityInputHandler` selection/marked-text ownership, mouse hit
  testing, copy/cut/paste, and specifications driven through the same route.
- [ ] **Text editing has no clipboard or undo history.** The native text input
  supports focus, caret motion, selection, keyboard deletion, controlled
  updates, submission, and IME composition. Close by routing platform clipboard
  operations and a bounded per-editor undo/redo history through the production
  GPUI input actions, with semantic specifications that never record contents.

- [ ] **HTTP cancellation and streaming.** The bounded
  asynchronous HTTP foundation supports explicit scheme, redirect, timeout,
  header, request-body, and response-body policy, and the workbench suppresses
  stale completions. Add a typed request handle with cooperative transport
  cancellation and bounded streamed upload/download progress before
  applications depend on either.

- [ ] **HTTP Workbench advanced document tools.** Add syntax-highlighted JSON
  and text response modes, cURL and collection import/export, and resizable
  split panes through production editor/layout primitives. Preserve request
  meaning and redact authentication material in every persisted or exported
  representation.

- [ ] **HTTP Workbench collections and structured validation.** Add bounded
  non-secret request history and named collections through `AppData`, excluding
  authorization, cookie, and proxy-authorization values by construction. Add
  structured JSON validation and multiple header/query rows with field-owned
  diagnostics before advertising environment or authentication editors.

- [ ] **Broker trusted HTTP destinations at runtime.** The provisioned origin
  grant pins non-literal DNS resolution, disables ambient proxies, rejects
  credential-bearing URLs, and rechecks redirects against the granted origin.
  Add user-visible named destination setup and consent backed by an OS
  credential store. Audit platform-specific resolver behavior and IPv4-mapped
  IPv6 classification before treating provisioning flags as user consent.

- [ ] **Native accessibility roles and names are not exported.** Buttons,
  checkboxes, and scroll regions have stable semantics in the canonical graph,
  but the GPUI host does not yet publish them to each operating system's
  accessibility API. Close with platform accessibility nodes verified by an
  external accessibility client, while retaining the same semantic names used
  by specifications.
- [ ] **Composite directory navigation has no roving focus.** A user can reach
  and activate every folder with Tab and Enter or Space. Close with a semantic
  list/list-item element whose Up, Down, Home, and End behavior, selected state,
  scroll-into-view behavior, scaling case, and operating-system accessibility
  mapping all use the production event path.

- [x] **Redis Explorer serializes nothing on its single stream.** Closed. The
  stream is no longer a field the whole application can reach: `Explorer.Link`
  holds it inside the in-flight request (`Busy`) and nowhere else, so the render
  function has no handle to hand a second request and cannot start one. A
  RESP connection is one ordered conversation, and ownership now says so in the
  type rather than in a flag someone must remember to check. Controls stay in
  place and go dead while a request owns the stream, and a completion hands the
  stream back from the state it was borrowed from, never from the task closure's
  captured copy. `examples/redis-explorer/specs/stream-ownership.scm` is the
  superseded-scan specification this entry said could not be written: it presses
  Refresh three times inside one scan and asserts the newest keyspace arrives
  with no error and exactly one scan's worth of traffic on the wire.

- [ ] **Audio is the one resource whose operations are not methods on its
  handle.** Every other host resource is a nominal type carrying its own
  operations, so a caller writes `store.read!(path)` and `pty.read!(opts)`.
  `Audio.Output` and `Audio.Track` are still plain aliases of their `Resource`
  representation with module-level `Audio.load!`, `Audio.play!` and the rest,
  because the pinned compiler cannot build an application that uses them in
  nominal form. Making both nominal and leaving the rest of the platform
  untouched, `roc check` on `examples/music-player` passes and
  `roc build examples/music-player/main.roc` never terminates -- it was left
  for fifty-five minutes of CPU against 5.1 seconds for the same example with
  `Audio` as aliases, with memory still climbing. Making only `Audio.Output`
  nominal segfaults the compiler outright. Nothing about music-player's own use
  is unusual: it holds the handles in application state and passes them through
  `Action.task`, which `image-library` and `file-explorer` also do with
  `Assets.Store` and `Files.Dir.Read` and which compile in seconds. Closing this
  needs the compiler defect fixed and reported upstream; the platform change
  itself is then the same one made for every other resource.

- [ ] **A resource handle captured by a task closure cannot be stored by its
  completion.** Writing `Tcp.Stream` back into application state from
  inside `resolve`, using the handle the surrounding `Action.task` captured,
  segfaults the process non-deterministically — the capture is released when the
  task's closure is, so the completion stores a dangling resource. Recovering the
  same handle from the state the completion is given is safe and is what Redis
  Explorer now does, but nothing in the API says which of the two is correct, and
  the wrong one fails as a crash rather than as a type error. Either the capture
  must keep the resource alive for the completion, or storing one must be
  rejected at compile time.

- [ ] **A window specification cannot wait for an HTTP request.** In the window
  runner `await-task` is `settle 2`, and a real `Http.Client.send!` over loopback does
  not land inside it: the readout is still "in flight" when the next step runs.
  Asking for more settling makes it worse rather than better — repeated
  `await-task` steps, or one `settle :frames 45`, leave the windowed host
  hanging until the 45-second watchdog kills it, and a run that ends with the
  request still outstanding aborts with `roc-gui host error: RocHost is not
  initialized`, so a worker completion is reaching a torn-down host. File and
  TCP worker tasks in the same runner settle normally, so this is specific to
  the HTTP path. The effect is that no window case can photograph a response, a
  status line, or a granted-authority readout that only a real reply produces:
  HTTP Workbench's window cases therefore cover the first frame and the refusal,
  which is everything reachable before the network, and its granted state is
  asserted only by the semantic runner.

- [ ] **Two concurrent worker completions have no ordered wait.** `await-task`
  applies one accepted completion, but when an application has two identical
  requests in flight the order they land in is not deterministic. Image
  Library's superseded folder scan is only observable while the older
  completion is being suppressed, so the claim cannot be asserted: a
  specification that checks the gallery is still empty after the first
  `await-task` passes or fails depending on which scan finished first.
  Suppression there is therefore covered only by the final state and the file
  counters, which are identical with and without the guard. An ordered or
  request-selective wait step would close it.
- [x] **Device Configurator has two unreachable status messages.** Closed. Both
  branches are gone, and they are gone in the stronger of the two available
  ways: `apply` and `disconnect` now take the connection -- and `apply` the
  configuration -- that they operate on, so there is no state in which either
  can be called without one. An unreachable message is not a safety net; it is
  a claim the type system should have been making, and now does.

  The half of the entry that asked for controls that explain themselves is
  honoured where a person is actually looking. Connect and Disconnect live on
  the device card and are never both offered, so before discovery neither
  exists rather than existing uselessly; Apply is the one control that is ever
  disabled, and the footer beside it says "The device has everything shown
  here" when it is. `connect-before-discovery.scm` and `reconnect.scm` now
  assert the absence of the control rather than the inertness of pressing it,
  which is the stronger claim.

  One thing this entry did not anticipate: the same reasoning found a real
  defect next door. Discovery empties the device list, and the open connection
  was reachable only from a card in that list, so discovering again while
  connected stranded the handle. Discovery is now withheld while a connection
  is open and says why, asserted by `discover-while-connected.scm`.

- [x] **Asset stores have no behaviour specification.** Closed. `music-player`
  adopts the API: it ships `assets/` with a `roc-assets.manifest`, reads
  `art/nocturne-cover.jpg` through `Assets.content_directory` with
  `with_manifest`, and draws it in the sleeve beside NOW PLAYING. Both paths are
  specified -- `specs/cover-art.scm` grants a content directory and asserts
  `(expect-asset-counters 1 0 1 1 0 142534)` alongside
  `(expect-image-bytes (role image :name "Cover art") 142534)`, and
  `specs/cover-art-denied.scm` withholds the grant and asserts the refusal,
  `(expect-asset-counters 0 1 0 0 0 0)`, with the quiet line the sleeve shows
  instead. The route from Roc through the ABI is now exercised end to end.

  One thing this entry did not anticipate: the grant vocabulary had no way to
  provision a content directory, so `--host-cap-assets` was reachable from a
  command line but not from a specification. `(assets "PATH")` was added to
  `spec::Grant` and to `docs/specifications.adoc`, and `expect-asset-counters`
  was added to the assertion reference, where it had been documented only in
  `docs/development.adoc`.

- [ ] **No asset root resolves relative to the application itself.** The three
  roots are the executable's directory, the process working directory, and the
  host-provisioned content directory. None of them is "the directory this
  application ships in", which is what `roc app.roc` actually wants: the
  executable is a build output in a temporary directory, and the working
  directory is wherever the shell happens to be. `music-player` therefore reads
  its cover from `working_directory("examples/music-player/assets")`, which is
  correct when an example is run from the checkout root as the README says and
  wrong from anywhere else. Closing this needs the application's own location to
  reach the host, which is packaging identity rather than an asset-surface
  change.

  It also cost a specification. `specs/cover-art-denied.scm` proved the missing
  cover state by withholding the content-directory grant; with a root that
  resolves without provisioning there is no way to make the read fail from a
  specification, so the case was removed rather than left asserting something it
  no longer caused. The refused open and refused read are still covered by the
  asset host's own tests.

- [ ] **A content directory is not an application identity.** A
  `ContentDirectory` store resolves to whatever `--host-cap-assets` names, which
  is development and packaging provisioning, not a stable per-application
  installed location. Until packaging identity exists, two applications run from
  the same host configuration share one content root, and an installed layout
  has nothing to resolve against.

- [ ] **Asset stores have no scaling case.** The manifest check is constant-time
  in the number of assets by construction, and one read is bounded at 64 MiB,
  but nothing measures an application reading many assets across many tasks.
  A scaling case belongs with the example that adopts the API.
- [ ] **An SVG's red and blue channels are exchanged when it is rendered.** A
  rasterised image is correct; an SVG is not. In `gpui` 0.2.2,
  `Image::to_image_data` (`platform.rs`) sends every raster format through a
  helper that converts the decoded RGBA to the BGRA the renderer wants, but the
  `ImageFormat::Svg` arm wraps `svg_renderer.render_pixmap`'s buffer directly
  and performs no such conversion. So `hsl(29,55%,35%)`, the warm brown
  `image-library`'s `collection-01.svg` is authored with, reaches the screen as
  a blue, and the fixtures authored as browns and an amber-to-violet sky present
  as blues and greens. PNG, JPEG, WebP, BMP, TIFF and GIF are unaffected.
  Decoding is GPUI's to own, and pre-rasterising SVG in this host would
  duplicate the decoder this platform deliberately does not reimplement, so this
  closes upstream. The vendored example icons are neutral greys, which are
  invariant under the exchange and therefore honest either way. Verify with a
  specification that samples a known pixel of a known fixture once a fix lands.
