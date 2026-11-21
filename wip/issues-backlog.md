# Issues backlog

- [ ] **Roc Boxy rebuild continuation copies.** The platform uses explicit
  continuation types in `platform/Internal.roc` to keep rebuild scaling cases
  within their execution budget on nightly `2026-11-20-3b29392`. Once a Roc
  nightly ships the fix for [roc-lang/roc#13331](https://github.com/roc-lang/roc/issues/13331),
  rerun the rebuild scaling specs and compare callback timings before deciding
  whether the annotations can be simplified.
- [ ] **Roc fast development linking on Windows with host DWARF.** Windows host
  packaging strips DWARF after separating the import members, and the
  normalization receipt records the transformation. Once a Roc nightly ships
  the fix for [roc-lang/roc#13338](https://github.com/roc-lang/roc/issues/13338),
  link and launch Counter on Windows with a DWARF-bearing host archive before
  deciding whether to retain the strip step as standard packaging policy.
- [ ] **Hosted macOS window driver occasionally stalls.** The same GPUI specs
  pass locally, but the macOS runner can hit the host watchdog at
  `driver-started`, including on successive launches. The macOS window job
  allows two fresh retries and uses a 90-second step budget and 120-second
  watchdog within its 180-second process deadline. Find why the driver stops
  progressing on hosted macOS and restore the default deadlines and retries.
- [ ] **FreeType distributor can time out on a cold CI cache.** The Blueprint
  CI job tries the official mirror and verifies the locked source bytes before
  placing them in the store. Move this fallback into the download recipe once
  Blueprint supports alternate URLs for a pinned source.
