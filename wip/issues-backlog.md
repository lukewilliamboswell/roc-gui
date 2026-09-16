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
  `Process.resize!` and specify the resulting PTY size without exposing a
  fixed-size product control.
- [ ] Add ANSI/VT cell parsing, wide and combining glyph layout, selection,
  clipboard policy, and URL recognition on top of the ordered PTY byte stream.
- [ ] Add tabs, nested split panes, focus navigation, pane zoom, and persisted
  workspace layouts using the existing mounted graph and event route.
- [ ] Add user-configurable shell-profile grants without exposing executable or
  environment selection as ambient application authority.

## Element appearance

- [ ] **Panel labels are never painted.** `Elem.panel`'s `label` is a semantic
  locator name, and several applications use it for a status phrase rather than
  a heading, so painting it as a header would both duplicate body text and move
  every existing layout. Close with an explicit heading on the panel element,
  distinct from the locator name, rendered with its own weight and size.

- [ ] **Lists carry no style of their own.** `Elem.virtual_list` and
  `Elem.scroll` take only a name, a row height, and their content, so a list has
  no ground, padding, radius, or row spacing. Found while giving `music-player`
  a dark queue: the list had to be wrapped in a padded panel for its surface,
  every row repaints that surface itself, and row spacing exists only because
  each row button is deliberately shorter than `row_height`. Close by giving
  both list elements the shared `Gui.Style` fields, with a separate row gap.
- [ ] **`Elem.text` has no style.** Colour and size reach a string only by
  inheritance from an enclosing row or column, so every typographic step costs a
  wrapper element that exists for no other reason. `music-player`'s wordmark and
  status line are each a one-child `row` whose only job is `fg` and `font_size`.
  Close with a styled text element carrying the same colour and size fields.
- [ ] **No shadow or elevation.** Surfaces separate from their ground only by
  `bg`, `border_color`, and `radius`. A raised card on a near-white ground wants
  a soft shadow, which on paper-light palettes is the only separation with
  enough contrast to read; `counter`'s cards fall back on a 1px rule that all
  but disappears against the ground it was chosen to sit quietly against. Close
  with a shadow field on `Gui.Style`.
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
- [ ] **An image's `width`, `height`, and `fit` do not size the picture.** A
  gallery wants one uniform thumbnail shape and one viewer image that fits the
  space left for it. With `fit: Cover` and `width: Px(88), height: Px(88)` the
  painted SVG keeps a size of its own inside the box, and with `height: Fill,
  grow: True` the viewer image is laid out past the bottom of the window instead
  of fitting it, so `examples/image-library/specs/window-gallery.scm` can only
  assert `expect-visible` for the selected image where `expect-on-screen` is the
  claim that matters. Close by making the declared box authoritative and `fit`
  the rule that maps pixels into it.

## Trust: measurements that can mislead a decision

- [ ] **All benchmark captures come from the headless runner.** No GPUI stage is
  measured. The capture backend is `semantic-headless`. Closes with the
  end-to-end runner below.

## Performance findings from the suite

Defects in the platform or host that the benchmark suite has exposed. Each
names the evidence so a fix can be verified against the same case.

- [ ] **The Roc development optimization mode miscompiles the deep tree scaling
  case on x64glibc.** An explicit `roc build --opt=dev` produces an executable
  that segfaults in `benchmarks/tree-shape/specs/deep-1k.scm`; the normal build
  mode and a build differing only by omission of `--opt=dev` pass. Minimize and
  report this compiler regression, then update the pinned compiler when fixed.

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
- [ ] **A scroll step for window specifications.** Found by driving
  `folder-browser`: a list application's rows below the fold cannot be reached,
  clicked, or photographed at all. A `(scroll LOCATOR ...)` step would close
  this. `(resize W H)` has landed and `settings-center`'s
  `specs/window-narrow.scm` proves a layout at two sizes `main.roc` never asks
  for.
- [ ] **Shared steps the window runner does not implement.** `drag`,
  `replace-text`, `clipboard-text`, `submit`, `await-ticks`,
  `revoke-file-grants`, the value and ordering assertions, and the owner
  counter assertions are all classified semantic-only because the window runner
  refuses them, not because they would be dishonest there. Implementing them
  would let one specification assert semantic truth and photograph it.
  `await-ticks` in particular must drive real timer ticks rather than settling,
  which is what made it wrong before it was reclassified.
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
- [ ] **Focus has no destination when navigation removes the focused control.**
  An ordinary patch now restores focus by role and stable semantic name when
  the control remains live, and dialog open and close keep their own policy.
  What is still unspecified is where focus goes when the focused control is
  gone from the next graph: it is simply dropped.
- [ ] **Composite directory navigation has no roving focus.** A user can reach
  and activate every folder with Tab and Enter or Space. Close with a semantic
  list/list-item element whose Up, Down, Home, and End behavior, selected state,
  scroll-into-view behavior, scaling case, and operating-system accessibility
  mapping all use the production event path.

- [ ] **Redis Explorer serializes nothing on its single stream.** Scan, inspect,
  and disconnect each borrow the same `pf.Tcp` stream and run on the worker
  pool, so two overlapping requests interleave their RESP frames on the wire.
  Pressing Refresh keys twice before the first scan completes ends in
  "Redis could not scan that key pattern" rather than the newest keyspace: the
  generation guard suppresses the stale completion correctly, but the newest
  request has already been corrupted. A superseded request must either be
  queued behind the stream or cancelled before the next one writes, which is a
  transport ownership decision rather than an application state fix. Until it
  is closed there is no specification for superseding a scan or an inspection.

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
- [ ] **Device Configurator has two unreachable status messages.** `disconnect`
  answers "No device is connected" and `apply` answers "Connect a device
  first", but the controls that would produce those presses are disabled in
  exactly those states, so neither string can ever be shown. Either the
  controls should stay enabled and explain themselves, or the branches should
  go.

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

- [ ] **`Program` has no effectful startup, so a store is opened on a task.**
  `Program.init` is a pure value, so an application that wants its banner
  present in the first frame cannot open a store and read it before the first
  render; it must render a loading state and fill it in from `Action.task`. That
  is a sound route and the documented one, but it means every asset-backed
  application writes the same three-state field. An effectful `init!` that
  blocks startup, as roc-ray's does, would remove it. That is a change to the
  program model rather than to the asset surface, and it was not made here.

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
