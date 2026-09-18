(test "Row boundaries: local edit among 10,000 compact siblings with memoization"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Create 10,000 rows"))
    (click (role button :name "Toggle compact view"))
    (expect-component-work :mounted 10000 :retired 10000)
    (expect-count (text-prefix "Row ") 10000)
    (expect-not-visible (role button :name "Select row 5000"))
    (mark-metrics)
    (click (role button :name "Increment row 5000"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-visible (text "Row 5000: 1"))))
