;; Drops captures on the real window through GPUI's own file-drop events: the
;; files enter the window over the target, are held there, and are dropped,
;; and GPUI hit-tests the drop. Photographs the start page answering files it
;; would open, the capture they open, the choice a drop on an open capture
;; offers, and the comparison it makes.
(test "the window opens and compares dropped captures"
  (grants)
  (steps
    (settle)
    (drag-files (role drop-target :name "Observatory") "fixture/compare/browse-100.rgstats")
    (screenshot "drag-over")
    (drop (role drop-target :name "Observatory") "fixture/compare/browse-100.rgstats")
    (await-task)
    (settle)
    (expect-selected (role tab :name "browse-100.rgstats"))
    (expect-on-screen (role row :name "Capture bar"))
    (screenshot "dropped")
    (drop (role drop-target :name "Observatory") "fixture/compare/browse-100-b.rgstats")
    (settle)
    (expect-on-screen (role button :name "Compare with this capture"))
    (screenshot "offer")
    (click (role button :name "Compare with this capture"))
    (await-task)
    (settle)
    (expect-selected (role tab :name "browse-100-b.rgstats"))
    (expect-on-screen (within (role row :name "Baseline verdict") (text "✓ comparable: Δ against the baseline · no A/A bound")))
    (expect-drop-counters 2 2 0)
    (expect-grants
      "document drop/consent-only root read,derive remembered"
      "document drop/consent-only root read,derive remembered"
      "sqlite drop/consent-only derived read,derive remembered"
      "sqlite drop/consent-only derived read,derive remembered")
    (screenshot "compared")))
