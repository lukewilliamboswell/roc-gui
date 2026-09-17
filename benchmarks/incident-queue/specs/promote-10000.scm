(test "Incident queue: promote the last of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Load 10000 incidents"))
    (mark-metrics)
    (click (role button :name "Promote incident 10100"))
    (expect-patch :kind keyed :staged 11 :removed 11)
    (expect-count (text-prefix "Incident ") 10000)
    (expect-before (text "Incident 10100 · open") (text "Incident 101 · open"))
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 2)))
