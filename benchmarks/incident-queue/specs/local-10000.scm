(test "Incident queue: local card edit among 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Load 10000 incidents"))
    (mark-metrics)
    (click (role button :name "Toggle incident 5000"))
    (expect-patch :kind replace :staged 11 :removed 11)
    (expect-count (text-prefix "Incident ") 10000)
    (expect-visible (text "Incident 5000 · acknowledged"))
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)))
