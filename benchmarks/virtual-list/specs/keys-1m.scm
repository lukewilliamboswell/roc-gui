;; The keyboard moves the selection through 1,000,000 rows produced on demand. End
;; selects the last row and brings it into view without building any row
;; between; Up moves one row within the view. Each press offers the chord to
;; the same four shortcuts, so resolving it costs the same at every scale.
(test "Virtual list: keyboard through 1,000,000 rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000000 :initial-size 1000000 :change-size 1)
  (steps
    (click (role button :name "Provide 1000000 rows"))
    (expect-rows (role virtual-list :name "Rows") :count 1000000 :first 0 :mounted 18)
    (expect-count (shortcut "end") 1)
    (mark-metrics)
    (key "end")
    (expect-visible (text "Selected: 999999"))
    (expect-rows (role virtual-list :name "Rows") :count 1000000 :first 999982 :mounted 18)
    (key "up")
    (expect-visible (text "Selected: 999998"))
    (expect-rows (role virtual-list :name "Rows") :count 1000000 :first 999982 :mounted 18)
    (expect-keyboard-counters 2 2 6 0)))
