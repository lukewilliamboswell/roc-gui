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
