(test "Incident queue: promote among 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (mark-metrics)
    (click (role button :name "Promote incident 100"))
    (expect-patch :kind keyed :staged 11 :removed 11)
    (expect-before (text "Incident 100 · open") (text "Incident 1 · open"))
    (expect-count (text-prefix "Incident ") 100)
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 2)))
