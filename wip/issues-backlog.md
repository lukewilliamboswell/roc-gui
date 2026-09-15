# Issues backlog

Gaps between the documented ideal state in `docs/` and the repository as it is.
Each entry names its effect and the change that closes it. Remove an entry when
the change lands; do not soften the docs to match the gap.

## Linker-input release adoption

- [ ] **ALSA still uses a bootstrap linker recipe.** Add an independently
  versioned ALSA interface producer and native probe, publish its tested archive
  from `main`, adopt its generated lock entry, and remove `third_party/alsa` and
  the ambient system-runtime check. Ordinary builds must then download and
  verify the locked archive exactly like every other external linker input.

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
- [ ] **Trusted file workflows remain incomplete.** Linux Wayland Open Project
  uses the production XDG Desktop Portal and records session/source/parent
  lineage, while `--host-cap-dir` remains development provisioning. Add Open
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
  `Process.resize!` and specify the resulting PTY size without exposing a
  fixed-size product control.
- [ ] Add ANSI/VT cell parsing, wide and combining glyph layout, selection,
  clipboard policy, and URL recognition on top of the ordered PTY byte stream.
- [ ] Add tabs, nested split panes, focus navigation, pane zoom, and persisted
  workspace layouts using the existing mounted graph and event route.
- [ ] Add user-configurable shell-profile grants without exposing executable or
  environment selection as ambient application authority.

## Trust: measurements that can mislead a decision

- [ ] **All benchmark captures come from the headless runner.** No GPUI stage is
  measured. The capture backend is `semantic-headless`. Closes with the
  end-to-end runner below.

## Performance findings from the suite

Defects in the platform or host that the benchmark suite has exposed. Each
names the evidence so a fix can be verified against the same case.

- [ ] **Full-root replacement remains superlinear at 100,000 rows.** The
  production 100,000-row sparse-update case confirms the effect after dense
  validation, host-owned child streaming, and consolidation of mounted node
  and parent storage. In a serial same-executable run, 10,000 to 100,000 rows
  grew from 9.47 ms to 139 ms overall. Roc callback work grew 11.4x, validation
  19.0x, and graph apply 20.2x; both lifecycle and measured-span allocated
  bytes grew 10.0x. Further work must preserve the generic tree-integrity
  checks and exact patch counters. The full-root rebuild itself is intentional
  application semantics, with row boundaries providing the local-update
  alternative.
- [ ] **Text and tree-shape families currently measure node count only.** Long
  and short messages at 10,000 rows differ by under 15%, and depth has no
  measurable effect, because the headless path has no layout or paint. These
  families become informative only with the GPUI runner.

## Runner: test what we fly

- [x] **End-to-end GPUI spec runner.** Delivered as window specifications:
  `crates/host/src/window_runner.rs` drives the production window from inside
  `Application::run`, `crates/host/src/probe.rs` records laid-out bounds from
  the production render path, and `crates/host/src/screenshot.rs` photographs
  the window or a located region. See `docs/specifications.adoc`. Real input
  Keyboard input is real, through `Window::dispatch_keystroke`; pointer input is
  simulated at the production handler, gated on real laid-out geometry, because
  GPUI exposes no usable pointer seam. See `docs/specifications.adoc`.
- [ ] **A real pointer seam.** Pointer input is currently simulated at the
  production click handler. GPUI 0.2.2 offers no alternative:
  `Window::dispatch_event` is `pub fn` but returns the crate-private
  `DispatchEventResult`, so it cannot be called from outside GPUI even
  discarding the result, and the simulated-mouse helpers are on
  `TestAppContext` behind `test-support`. Real pointer input therefore needs
  one of: making `DispatchEventResult` public upstream, OS-level event posting
  (macOS `CGEvent`, which needs Accessibility permission and moves the physical
  cursor), or a compositor seam on Wayland. Until then `click` cannot exercise
  GPUI's dispatch tree, occlusion by unrelated elements, or hover styling, and
  there is deliberately no `hover` step.
- [ ] **Keyboard focus is dropped by ordinary state updates.** Found by
  `examples/counter/window-specs/keyboard.scm`: focusing a button and
  activating it with a real `Space` works once, and the control has lost
  keyboard focus by the next frame, so a second activation goes nowhere. Focus
  restoration in `Runtime::apply_to_gpui` runs only on dialog open and close
  transitions; a patch that re-mounts the focused control has no restoration
  path, and `find_focus_identity` is never consulted for it. Keyboard-only
  operation of any control that changes state is therefore broken.
- [ ] **Bring off-screen targets on screen.** `expect-on-screen` distinguishes
  laid out from actually visible, but large row cases place targets outside the
  window and the platform still has no scrolling feature to bring them into
  view.
- [ ] **Layout, paint, and presentation spans** owned by the GPUI side of the
  host. Presentation may need a Wayland frame callback.
- [ ] **CI compositor.** Benchmark jobs run the real Wayland backend under a
  headless compositor such as sway or cage. For Sway this requires a headless
  wlroots output, software rendering on workers without a GPU, and pointer
  movement plus press/release over its IPC or virtual-pointer protocol. The job
  must prove that GPUI receives the real Wayland event before benchmark captures
  are accepted; merely opening a window is insufficient.
- [ ] **Demote the headless runner to smoke.** Remove benchmark policy from it
  and make the scaling and compare views refuse `semantic-headless` captures.

- [ ] **Split the specification reference by audience.**
  `docs/specifications.adoc` serves an application author and a platform
  contributor from one 450-line file, so a user's path runs through fixture
  metadata for this repository's own examples. `docs/testing-your-app.adoc`
  now carries the user-facing path; the reference should lose the fixture block
  to `development.adoc` and be retitled.
- [ ] **Capture the window, not the screen region.** `screencapture -R` takes a
  screen rectangle, so anything drawn over the window lands in the evidence; a
  1280x800 window on a display with the dock visible photographs the dock. A
  window-targeted capture (`screencapture -l<windowid>`, which reads the
  window's own contents) would be immune, at the cost of cropping in process
  from the returned image rather than in the request. The `image` crate is
  already a dependency; the missing piece is the window id, which GPUI does not
  expose and which would need the pid-to-window mapping the capture currently
  avoids needing.
- [ ] **Per-canvas-item screenshot regions.** Only a canvas node's own
  rectangle is recorded, so `(screenshot :region (role canvas-item ...))` is a
  parse error rather than a silent whole-canvas photograph. Recording primitive
  geometry would reuse `canvas_target`'s hit-testing arithmetic.
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
- [ ] **Focus is not restored across replaced subtrees.** Keyboard focus works
  for each live GPUI control, but a Roc state update replaces that control's
  native entity. Dialog open/close is the deliberate exception: its runtime
  policy restores the semantic opener. Close the general gap by carrying role and stable semantic name across a
  successful patch when the corresponding control remains live, and specify
  the destination when navigation removes the focused control.
- [ ] **Composite directory navigation has no roving focus.** A user can reach
  and activate every folder with Tab and Enter or Space. Close with a semantic
  list/list-item element whose Up, Down, Home, and End behavior, selected state,
  scroll-into-view behavior, scaling case, and operating-system accessibility
  mapping all use the production event path.
