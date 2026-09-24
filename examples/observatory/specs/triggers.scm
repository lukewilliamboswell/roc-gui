;; Cycles are grouped by trigger and patch kind within one measurement phase,
;; measured by default.
(test "the triggers table groups cycles by phase, trigger, and patch kind"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-visible (text "TRIGGERS · measured · by median · warmups excluded"))
    (expect-visible (within (role column :name "Triggers") (text "click")))
    (expect-visible (within (role column :name "Triggers") (text "task")))
    (expect-count (within (role column :name "Triggers") (text "replace")) 2)
    (expect-not-visible (within (role column :name "Triggers") (text "init")))
    (click (role button :name "Phase initialization"))
    (expect-visible (within (role column :name "Triggers") (text "init")))
    (expect-visible (within (role column :name "Triggers") (text "mount")))
    (click (role button :name "Phase interactive"))
    (expect-visible (text "No cycles were recorded in the interactive phase."))))
