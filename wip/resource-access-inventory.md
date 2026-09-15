# Resource access inventory

Audited at `fdec6a5`. “Unverified” is intentional: it means the repository does
not contain evidence for the claim. Public Roc entry points are in `platform/`;
their hosted symbols are enumerated by `platform/main.roc` and mirrored in
`platform/Host.roc`/`HostGlue.roc` and generated `roc_platform_abi.rs`.

The current enforcement boundary is the linked native process. Opaque Roc
handles prevent accidental use of an operation without the matching token, but
do not confine hostile Roc dependencies, replacement executables, native
libraries, decoders, or the trusted host itself.

| Surface | API / ABI and owner | Ambient authority and grant source | Scope, derivation, lifetime, revocation | Budget / enforcement | Verification |
| --- | --- | --- | --- | --- | --- |
| UI graph and input | `Elem`, `Event`; `roc_gui_node_*`, dispatch/apply; `lib.rs`, `bridge.rs` | GPUI window/input owned by linked host; no resource grant | Node IDs and routes live until subtree replacement; stale IDs rejected; no security revocation | Graph/node/input bounds; structural validation | Host bridge/input tests and SCM semantics; compositor delivery and OS accessibility **Unverified** |
| Timers/clocks | `Timer`; `roc_gui_timer_*`; `timers.rs` | Host monotonic waits, automatically available | Opaque timer, process lifetime, explicit cancel; no precision privacy policy | 256 active; interval bounds | timer/subscription specs; quota saturation and clock fingerprinting policy **Unverified** |
| Secure randomness | No public API | Native dependencies may access OS randomness inside process | Absent platform contract; indirect native access **Unverified** | None | Reachability and future quota **Unverified** |
| Read project/files | `Files.pick_directory!`, `Dir.list!/open_read_dir!/read!`; `roc_files_*`; `files.rs` | Linux Open Project uses XDG Desktop Portal; `cap_std::ambient_authority` exists only at the portal/provisioning broker boundary; `--host-cap-dir` is development provisioning | Root source/session metadata; children carry parent and inherited source; refcount cleanup only, no revocation | One prompt at a time plus refusal cooldown; 10,000 entries, 4 MiB names, 64 MiB file; final symlinks not followed | File and selection owner counters/specs; external portal parenting, protected identity, accessibility, sibling denial, root/child revocation and races **Unverified** |
| Private app data | `Files.app_data!`, UTF-8 read/atomic write; `roc_files_app_data/dir_*`; `app_data.rs` | Host opens/creates configured ambient path | Read-write root, flat child keys; process/refcount lifetime; app identity/isolation/uninstall/revocation **Unverified** | 128-byte key, 1 MiB value; no quota | Settings specs; cross-app isolation, stable identity, disk-full/cleanup **Unverified** |
| SQLite | `Sqlite.open_read!/query!`; `roc_sqlite_*`; `sqlite.rs` | Derived from `DirRead`; bytes copied through no-follow child open | Independent in-memory read-only snapshot; handle refcount cleanup; parent revocation semantics **Unverified** | 64 MiB DB, 64 KiB SQL, 256 columns, 10,000 rows, 16 MiB values; authorizer denies writes/attach | Database Browser error/counter/scale specs; extension/function escape audit and revocation **Unverified** |
| HTTP | `Http.acquire!/send!`; `roc_http_*`; `http.rs` | Host-configured origin string; linked HTTP/TLS/DNS stack has network authority | Client handle represents one configured origin; redirect enforcement and DNS rebinding confinement **Unverified**; no cancellation/revocation | 60 s timeout ceiling, redirect/request/response bounds | Workbench semantic errors/scale; actual destination, proxy, credential and private-address enforcement **Unverified** |
| Raw TCP | `Tcp.connect!/read/write/close`; `roc_tcp_*`; `tcp.rs` | Exact host-configured numeric socket address | One endpoint and stream; explicit close/refcount cleanup; no revocation | 2 s timeout, 1 MiB read, 16 MiB write | Redis specs and stream counter; brokered trusted connect and revocation **Unverified** |
| Processes/PTY | `Process.acquire!/spawn/read/write/resize/cancel`; `roc_process_*`; `process.rs` | Host chooses fixed profile; implementation spawns `/bin/sh` with a controlled fixture/local-shell program | Grant derives PTY; cancel kills session; inherited descriptor/environment confinement **Unverified** | 64 active, 64 KiB I/O, bounded dimensions | Terminal specs and process counters; hostile shell profile, inheritance and platform isolation **Unverified** |
| HID devices | `Device.acquire!/discover/connect/transact/close`; `roc_device_*`; `device.rs` | Host config selects virtual or physical VID/PID; `hidapi` accesses OS devices | Grant derives one connection; close/refcount cleanup; hot-plug/revocation absent | 32 active, 4096-byte reports, 2 s physical read | Virtual protocol/error/counter/scale specs; trusted device chooser and OS scoping **Unverified** |
| Audio output | `Audio.acquire!/load/play/pause/seek/status/stop`; `roc_audio_*`; `audio.rs` | Host enables system output or paced null sink; Rodio/CPAL opens device | Output derives tracks loaded from `DirRead`; stop/refcount cleanup; device-loss/revocation absent | Decoder/file bounds inherited; live/operation counters; output quota **Unverified** | Music specs and audio counters; trusted routing and decoder confinement **Unverified** |
| System monitoring | `SystemMonitor.acquire!/sample/close`; `roc_system_*`; `system_monitor.rs` | Host enables real `sysinfo` sampler or deterministic unavailable/virtual source | Sampler handle, explicit close/refcount cleanup; observes host processes when enabled | 16 samplers, 10,000 processes | Monitor semantic/counter/scale specs; platform permission matrix and identifier privacy beyond rendered names **Unverified** |
| Clipboard text | `Clipboard.acquire!/read_text!/write_text!`; `roc_clipboard_*`; `clipboard.rs` | Host enables system clipboard or fixture backend | Session handle; no compositor notification/revocation; passive observation authority | 64 KiB text; operation/live counters | Clipboard specs/privacy counters; trusted activation and Wayland ownership semantics **Unverified** |
| Image decoding | `Elem.image` lowers encoded bytes; GPUI image asset owner in `lib.rs` | Bytes already in app state; native decoder libraries execute in linked process | No path/URL authority; decoded cache lifetime and failure callback **Unverified** | Encoded byte list bounded by source operation; decoded memory budget absent | image byte evidence; decoder success/failure, cache eviction and compromised-decoder confinement **Unverified** |
| Observatory/diagnostics | Host flags; `observatory.rs`, analyzer scripts | Opens explicitly selected capture output; reads `/proc`, current executable and OS facts | Recorder process lifetime; no app-facing handle/revocation | bounded queue/output; privacy allow-list | recorder/privacy tests; path destination broker and exhaustive side-channel review **Unverified** |
| Drag-and-drop / file clipboard / sharing | No public resource API | Native GPUI/OS routes may exist below dependencies | No grant semantics | None | Reachability and denial **Unverified** |
| URI opening / registered-app reveal | No public API | `open` crate is linked transitively; direct reachability from Roc **Unverified** | No grant semantics | None | Binary/dependency reachability **Unverified** |
| Webviews | No public API | Dependency/native reachability **Unverified** | No origin/storage/cookie grant model | None | **Unverified** |
| Microphone, camera, screen capture | No public API | CPAL is linked for output; input reachability and OS APIs **Unverified** | No trusted indicator or session grant | None | **Unverified** |
| Native extensions/dynamic loading | No public API; native host and dependencies are statically/dynamically linked | Replacement host and linked libraries execute with process authority | Outside typed-handle model | Packaging/signing/confinement absent | Compiler/runtime/linker bypass audit **Unverified** |
| IPC/listening sockets | No public API | Dependencies and process child may expose indirect IPC; inherited descriptors **Unverified** | No grant model | None | `/proc`, Unix socket, DBus and descriptor audit **Unverified** |
| Global input/automation/accessibility | No public global-input API; semantic runner is internal | GPUI/compositor/OS accessibility facilities | Semantic locators are not OS accessibility grants | No rate/authorization policy | Headless semantics only; external accessibility and global-input denial **Unverified** |

## Platform and enforcement matrix

| Target | Shipped execution path | Present enforcement claim | Required enforcement before hostile apps are supported |
| --- | --- | --- | --- |
| Linux x86-64, Wayland | Linked Roc application and Rust/GPUI host | Trusted application only; registries and typed handles prevent accidental misuse, not process escape | Confined application process, trusted broker outside it, XDG portals or equivalent protected selection, syscall/filesystem/network/device policy, signed packaging, and end-to-end compositor tests |
| Linux, other architectures/display servers | No shipped target | None | Port and verify the complete Linux boundary; **Unverified** |
| macOS | No shipped target | None | Sandbox/entitlements, trusted panels, broker lifecycle, signing/notarization, and native end-to-end tests; **Unverified** |
| Windows and other systems | No shipped target | None | Platform-specific confinement and trusted broker design; **Unverified** |

## Threat model and decision

The supported model trusts the Roc application, its Roc dependencies, the
compiler/runtime, linked native host, and native libraries. It protects against
accidental authority confusion and malformed values at ABI/registry boundaries.
It does not protect against hostile application source, a malicious dependency,
a replacement executable, or a compromised decoder.

The enforcement decision for a future untrusted-application model is process
separation: a confined application process receives opaque broker tokens, while
a smaller trusted broker owns protected Open, Save, Connect, Share, clipboard,
device, and capture interactions. The OS enforces denial even if application
code bypasses the Roc API. Until that path, packaging identity, and platform
tests exist, untrusted applications are unsupported and confinement claims are
blocked.
