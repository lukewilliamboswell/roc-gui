(test "Incident queue: promote among 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Load 1000 incidents"))
    (mark-metrics)
    (click (role button :name "Promote incident 1100"))
    (expect-patch :kind keyed :staged 11 :removed 11)
    (expect-before (text "Incident 1100 · open") (text "Incident 101 · open"))
    (expect-count (text-prefix "Incident ") 1000)
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 2)))
