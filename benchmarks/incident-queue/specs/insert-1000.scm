(test "Incident queue: insert at front of 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1001 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Load 1000 incidents"))
    (mark-metrics)
    (click (role button :name "Add urgent incident"))
    (expect-patch :kind keyed :staged 21 :removed 10)
    (expect-count (text-prefix "Incident ") 1001)
    (expect-before (text "Incident 1101 · open") (text "Incident 101 · open"))
    (expect-component-work :rendered 3 :compared 0 :skipped 0 :mounted 1 :retired 0 :registry-visits 3 :keyed-order-visits 6 :keyed-snapshot-items 0)))
