;; The scaling case for one long capture: a browsing session of 10,000 cycles.
;; Opening it reads the first page of its cycles, and the cycle list builds
;; only the rows a screen shows and one screen below, whatever the length.
;; Jumping to the fastest cycle reads the page at the far end and builds the
;; rows around it, without reading or building any between.
(test "open a session of 10000 cycles and jump through its cycle list"
  (grants
    (directory "fixture/session"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (mark-metrics)
    (click (role button :name "Capture database-browser-session.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-visible (text "CYCLES · measured · every trigger · slowest first · 10000"))
    (expect-rows (role virtual-list :name "Cycles") :count 10000 :first 0 :mounted 70)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")) 70)
    (click (role button :name "Scroll to fastest cycle"))
    (await-task)
    (expect-rows (role virtual-list :name "Cycles") :count 10000 :first 9930 :mounted 70)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")) 70)
    (expect-count (within (role virtual-list :name "Cycles") (text "reading")) 0)
    ; the first page was let go for the last, so jumping back holds the rows'
    ; places until it is read again
    (click (role button :name "Scroll to slowest cycle"))
    (expect-rows (role virtual-list :name "Cycles") :count 10000 :first 0 :mounted 70)
    (expect-count (within (role virtual-list :name "Cycles") (text "reading")) 70)
    (await-task)
    (expect-count (within (role virtual-list :name "Cycles") (text "reading")) 0)))
