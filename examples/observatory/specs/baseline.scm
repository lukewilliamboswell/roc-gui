;; A baseline is set once and applies everywhere: the triggers table, the
;; cycle inspector, and Memory gain a Δ and a ratio against it, ordered by
;; |Δ|. An A/A capture of the baseline's executable bounds every Δ, and one
;; that fails the gate is refused with its key.
(test "a baseline adds deltas to every view and an A/A capture bounds them"
  (grants
    (directory "fixture/compare"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture browse-100.rgstats"))
    (await-task)
    (click (role button :name "Set as baseline"))
    (click (role button :name "Back to captures"))
    (click (role button :name "Capture browse-100-b.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Baseline verdict") (text "✓ comparable: Δ against the baseline · no A/A bound")))
    (click (role button :name "Interactions"))
    (expect-visible (text "TRIGGERS · measured · by |Δ| · warmups excluded"))
    (expect-visible (role button :name "Sort triggers by delta"))
    (expect-visible (within (role row :name "Noise click replace") (text "no A/A bound")))
    (expect-visible (within (role row :name "Noise task replace") (text "no A/A bound")))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (within (role row :name "Baseline delta") (text-prefix "vs baseline median ")))
    (click (role button :name "Memory"))
    ; allocation counts are deterministic, so a rerun allocates exactly what
    ; the baseline did
    (expect-visible (text "Δ bytes x̄"))
    (expect-visible (within (role row :name "Allocation task platform_lowering") (text "+0 B")))
    (expect-visible (within (role row :name "Allocation task platform_lowering") (text "1.00×")))
    (click (role button :name "Compare"))
    (expect-visible (within (role row :name "A/A verdict") (text "No A/A capture: deltas are shown without a noise bound.")))
    ; a contended capture cannot bound noise
    (click (role button :name "Use browse-100-jobs-2.rgstats as A/A"))
    (await-task)
    (expect-visible (within (role row :name "A/A verdict") (text "✗ refused: job_count differs: 1 against 2")))
    (click (role button :name "Use browse-100-aa.rgstats as A/A"))
    (await-task)
    ; the A/A capture keeps a connection of its own beside the baseline's and
    ; the open capture's, and the refused one it replaced is closed
    (expect-sqlite-counters 3 10 99)
    (expect-visible (within (role row :name "A/A verdict") (text-prefix "✓ browse-100-aa.rgstats bounds every Δ")))
    (expect-visible (within (role row :name "Baseline verdict") (text "✓ comparable: Δ against the baseline · A/A browse-100-aa.rgstats")))
    (click (role button :name "Interactions"))
    (expect-not-visible (within (role column :name "Triggers") (text "no A/A bound")))
    (expect-visible (role row :name "Noise click replace"))
    (click (role button :name "Memory"))
    (expect-visible (within (role row :name "Noise task platform_lowering") (text "within noise")))
    (click (role button :name "Compare"))
    (click (role button :name "Use browse-100-aa.rgstats as A/A"))
    (expect-visible (within (role row :name "A/A verdict") (text "No A/A capture: deltas are shown without a noise bound.")))))
