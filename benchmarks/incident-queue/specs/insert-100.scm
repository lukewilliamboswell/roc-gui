(test "Incident queue: insert at front of 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 101 :initial-size 100 :change-size 1)
  (steps
    (mark-metrics)
    (click (role button :name "Add urgent incident"))
    (expect-patch :kind replace :staged 21 :removed 10)
    (expect-count (text-prefix "Incident ") 101)
    (expect-before (text "Incident 101 · open") (text "Incident 1 · open"))
    (expect-component-work :rendered 2 :compared 100 :skipped 100 :mounted 1 :retired 0 :registry-visits 102)))
