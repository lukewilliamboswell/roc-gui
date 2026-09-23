;; The slowest cycles of a phase are listed slowest first, each with a stacked
;; bar of callback, validate, apply, and unattributed time. Choosing a trigger
;; in the triggers table narrows the list to its cycles.
(test "the cycle list orders a phase's cycles by duration and filters by trigger"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-visible (text "CYCLES · measured · every trigger · slowest first · 6"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 6)
    (expect-count (within (role virtual-list :name "Cycles") (text "task")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "click")) 3)
    (expect-before
      (role row :name "Cycle row r4 #7")
      (role row :name "Cycle row r4 #6"))
    (expect-visible (role row :name "Cycle bar r4 #7"))
    (expect-visible (within (role row :name "Cycle legend") (text "unattributed")))
    (expect-not-visible (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")))
    (click (role button :name "Filter click replace"))
    ; choosing a trigger renders the Interactions view and not the window: the
    ; empty inspector is kept, and the three rows filtered out retire
    (expect-component-work :rendered 6 :skipped 1 :mounted 0 :retired 3)
    (expect-visible (text "CYCLES · measured · click · replace · slowest first · 3"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "task")) 0)
    (click (role button :name "Filter click replace"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 6)
    (click (role button :name "Phase initialization"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "init")) 3)))
