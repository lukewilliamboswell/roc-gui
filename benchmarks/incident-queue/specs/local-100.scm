(test "Incident queue: local edit among 100"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (mark-metrics)
    (click (role button :name "Toggle incident 50"))
    (expect-patch :kind replace :staged 11 :removed 11)
    (expect-visible (text "Incident 50 · acknowledged"))
    (expect-count (text-prefix "Incident ") 100)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)))
