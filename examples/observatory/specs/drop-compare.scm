;; A capture dropped on an open capture waits for a choice (US-4): open it in
;; a tab of its own, or compare it with the capture on screen, which becomes
;; the baseline. Comparing is the baseline every view already applies, so the
;; dropped capture opens at Compare with its gate passed.
(test "a capture dropped on an open capture opens or compares with it"
  (grants
    (file "fixture/compare/browse-100.rgstats"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-selected (role tab :name "browse-100.rgstats"))
    (drop (role drop-target :name "Observatory") "fixture/compare/browse-100-aa.rgstats")
    (expect-visible (role dialog :name "Dropped capture"))
    (expect-visible (within (role dialog :name "Dropped capture") (text "browse-100-aa.rgstats")))
    ; the drop granted the file already; putting it down keeps nothing open
    (click (role button :name "Cancel drop"))
    (expect-not-visible (role dialog :name "Dropped capture"))
    (expect-selected (role tab :name "browse-100.rgstats"))
    (expect-drop-counters 1 1 0)
    (drop (role drop-target :name "Observatory") "fixture/compare/browse-100-aa.rgstats")
    (click (role button :name "Open"))
    (await-task)
    (expect-selected (role tab :name "browse-100-aa.rgstats"))
    (expect-not-selected (role tab :name "browse-100.rgstats"))
    (expect-visible (within (role row :name "Baseline verdict") (text "none: deltas appear once a baseline is set")))
    (drop (role drop-target :name "Observatory") "fixture/compare/browse-100-b.rgstats")
    (click (role button :name "Compare with this capture"))
    (await-task)
    (expect-selected (role tab :name "browse-100-b.rgstats"))
    (expect-not-selected (role tab :name "◆ browse-100-aa.rgstats"))
    (expect-visible (text "COMPARABILITY · A: browse-100-aa.rgstats ◆ baseline · B: browse-100-b.rgstats"))
    (expect-visible (within (role row :name "Baseline verdict") (text "✓ comparable: Δ against the baseline · no A/A bound")))
    (expect-drop-counters 3 3 0)
    (expect-recent-counters 3 0 0 0 3)))
