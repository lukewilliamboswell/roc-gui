(test "Build 1,000 translated rows"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000)
  (steps
    (expect-visible (text "Rows: 0"))
    (mark-metrics)
    (click (role button :name "Build 1,000 rows"))
    (expect-visible (text "Rows: 1000"))
    (expect-visible (text "Row 1000: 0"))))
