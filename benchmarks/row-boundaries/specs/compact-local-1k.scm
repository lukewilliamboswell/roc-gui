(test "Row boundaries: local edit among 1,000 compact siblings with memoization"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Create 1,000 rows"))
    (click (role button :name "Toggle compact view"))
    (expect-component-work :mounted 1000 :retired 1000)
    (expect-count (text-prefix "Row ") 1000)
    (expect-not-visible (role button :name "Select row 500"))
    (mark-metrics)
    (click (role button :name "Increment row 500"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-visible (text "Row 500: 1"))))
