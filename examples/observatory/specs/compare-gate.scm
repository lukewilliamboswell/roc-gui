;; Two captures are compared key by key before any delta is read. An A/A pair
;; passes every key; the same benchmark run with two jobs fails job_count and
;; timing_quality, and then no delta is shown anywhere.
(test "the comparability sheet gates a baseline key by key"
  (grants
    (directory "fixture/compare"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture browse-100.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Baseline verdict") (text-prefix "none")))
    (click (role button :name "Set as baseline"))
    ; only the baseline bar and the tab that now wears ◆ render: the capture
    ; and trust bars, the view rail, the Overview, which shows no delta, and
    ; the inspector are kept
    (expect-component-work :rendered 3 :skipped 5 :mounted 0 :retired 0)
    (expect-visible (text "◆ browse-100.rgstats"))
    (click (role button :name "Back to captures"))
    (click (role button :name "Capture browse-100-aa.rgstats"))
    (await-task)
    ; the baseline keeps its own connection beside the open capture's
    (expect-sqlite-counters 2 8 54)
    (expect-visible (within (role row :name "Baseline verdict") (text-prefix "✓ comparable")))
    (click (role button :name "Compare"))
    (expect-visible (text "COMPARABILITY · A: browse-100.rgstats ◆ baseline · B: browse-100-aa.rgstats"))
    (expect-count (within (role column :name "Comparability") (text "✓")) 19)
    (expect-count (within (role column :name "Comparability") (text "✗")) 0)
    (expect-visible (within (role row :name "Comparability verdict") (text-prefix "⇒ comparable")))
    (click (role button :name "Interactions"))
    (expect-visible (role button :name "Sort triggers by delta"))
    (click (role button :name "Back to captures"))
    (click (role button :name "Capture browse-100-jobs-2.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Baseline verdict") (text "✗ incomparable: job_count differs: 1 against 2; timing_quality differs: isolated against partial-contended. No deltas are shown.")))
    (click (role button :name "Compare"))
    (expect-visible (within (role row :name "Gate job_count") (text "✗")))
    (expect-visible (within (role row :name "Gate timing_quality") (text "timing_quality differs: isolated against partial-contended")))
    (expect-visible (within (role row :name "Gate spec_hash") (text "✓")))
    (expect-count (within (role column :name "Comparability") (text "✗")) 2)
    (expect-visible (within (role row :name "Comparability verdict") (text "⇒ incomparable: no deltas are shown. 2 of 19 keys fail.")))
    ; an incomparable pair shows no delta in any view
    (click (role button :name "Interactions"))
    (expect-not-visible (role button :name "Sort triggers by delta"))
    (expect-visible (text "TRIGGERS · measured · by median · warmups excluded"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-not-visible (role row :name "Baseline delta"))
    (click (role button :name "Memory"))
    (expect-not-visible (text "Δ bytes x̄"))
    (click (role button :name "Clear baseline"))
    (expect-visible (within (role row :name "Baseline verdict") (text-prefix "none")))))
