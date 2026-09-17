(test "Incident queue: local edit among 1,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Load 1000 incidents"))
    (mark-metrics)
    (click (role button :name "Toggle incident 600"))
    (expect-patch :kind replace :staged 11 :removed 11)
    (expect-visible (text "Incident 600 · acknowledged"))
    (expect-count (text-prefix "Incident ") 1000)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)))
