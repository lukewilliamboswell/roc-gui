(test "Row boundaries: local edit among 100 compact siblings"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Create 100 rows"))
    (click (role button :name "Toggle compact view"))
    (expect-component-work :mounted 100 :retired 100)
    (expect-count (text-prefix "Row ") 100)
    (expect-not-visible (role button :name "Select row 50"))
    (mark-metrics)
    (click (role button :name "Increment row 50"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-visible (text "Row 50: 1"))))
