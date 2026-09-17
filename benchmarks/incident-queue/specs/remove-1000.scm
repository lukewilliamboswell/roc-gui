(test "Incident queue: remove from 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 999 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Load 1000 incidents"))
    (mark-metrics)
    (click (role button :name "Dismiss incident 600"))
    (expect-patch :kind keyed :staged 10 :removed 21)
    (expect-count (text-prefix "Incident ") 999)
    (expect-not-visible (role row :name "Queue entry 600"))
    (expect-component-work :rendered 2 :compared 0 :skipped 0 :mounted 0 :retired 1 :registry-visits 2)))
