(test "Update the last of 10,000 translated rows"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000)
  (steps
    (click (role button :name "Build 10,000 rows"))
    (expect-visible (text "Row 10000: 0"))
    (mark-metrics)
    (click (role button :name "Row 10000 increment"))
    (expect-visible (text "Row 10000: 1"))
    (expect-visible (text "Row 1: 0"))))
