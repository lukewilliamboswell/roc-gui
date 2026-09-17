(test "Incident queue: remove from the middle of 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 9999 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Load 10000 incidents"))
    (mark-metrics)
    (click (role button :name "Dismiss incident 5100"))
    (expect-patch :kind keyed :staged 10 :removed 21)
    (expect-count (text-prefix "Incident ") 9999)
    (expect-not-visible (role row :name "Queue entry 5100"))
    (expect-visible (text "Dismissed or replaced: 1"))
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 1 :registry-visits 2)))
