;; The keyboard moves the selection through 10,000 rows held as items, every
;; one mounted in the graph. The graph resolves a chord by walking from focus
;; and asking the regions that declare shortcuts, never the rows, so a press
;; compares the same shortcuts as it does over an empty list.
(test "Virtual list: keyboard through 10,000 loaded rows"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Load 10000 rows"))
    (expect-count (button-prefix "Select virtual row ") 10000)
    (mark-metrics)
    (key "down")
    (expect-visible (text "Selected: 0"))
    (key "down")
    (expect-visible (text "Selected: 1"))
    (expect-keyboard-counters 2 2 2 0)))
