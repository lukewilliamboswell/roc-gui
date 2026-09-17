(test "Incident queue: remove from 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 99 :initial-size 100 :change-size 1)
  (steps
    (mark-metrics)
    (click (role button :name "Dismiss incident 50"))
    (expect-patch :kind keyed :staged 10 :removed 21)
    (expect-count (text-prefix "Incident ") 99)
    (expect-not-visible (role row :name "Queue entry 50"))
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 1 :registry-visits 2 :keyed-order-visits 4 :keyed-snapshot-items 0)))
