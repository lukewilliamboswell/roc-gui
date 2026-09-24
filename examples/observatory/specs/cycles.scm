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
    ; each click names the button it reached by kind and structural identity,
    ; never by its label; a task completion reached no element
    (expect-count (within (role virtual-list :name "Cycles") (text-prefix "button ")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "no target")) 3)
    (expect-before
      (role row :name "Cycle row r4 #7")
      (role row :name "Cycle row r4 #6"))
    (expect-visible (role row :name "Cycle bar r4 #7"))
    (expect-visible (within (role row :name "Cycle legend") (text "unattributed")))
    (expect-not-visible (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")))
    (click (role button :name "Filter click replace"))
    ; choosing a trigger reads its cycles. While they are read the list holds
    ; their places, and the six rows of every trigger retire; the empty
    ; inspector, the tabs, the capture bar, trust banner, and baseline bar are
    ; kept, and the distribution renders for the new filter
    (expect-component-work :rendered 6 :skipped 6 :mounted 0 :retired 6)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 0)
    (expect-count (within (role virtual-list :name "Cycles") (role row :name "Cycle row pending 3")) 1)
    (await-task)
    ; the answer renders the Interactions view and not the window: the list
    ; mounts the three rows read, and the inspector and the tabs are still kept
    (expect-component-work :rendered 7 :skipped 8 :mounted 3 :retired 0)
    (expect-visible (text "CYCLES · measured · click · replace · slowest first · 3"))
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "task")) 0)
    (click (role button :name "Filter click replace"))
    (await-task)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 6)
    (click (role button :name "Phase initialization"))
    (await-task)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r")) 3)
    (expect-count (within (role virtual-list :name "Cycles") (text "init")) 3)))
