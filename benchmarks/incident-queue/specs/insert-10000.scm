(test "Incident queue: insert at front of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10001 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Load 10000 incidents"))
    (mark-metrics)
    (click (role button :name "Add urgent incident"))
    (expect-patch :kind replace :staged 21 :removed 10)
    (expect-count (text-prefix "Incident ") 10001)
    (expect-before (text "Incident 10101 · open") (text "Incident 101 · open"))
    (expect-component-work :rendered 2 :compared 10000 :skipped 10000 :mounted 1 :retired 0 :registry-visits 10002)))
