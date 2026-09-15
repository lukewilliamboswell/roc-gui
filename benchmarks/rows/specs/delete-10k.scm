(test "Rows: delete within 10,000"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 9999 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Create 10,000 rows"))
    (mark-metrics)
    (click (role button :name "Delete row 5000"))
	(expect-patch :kind replace :staged 40011 :removed 40015)
    (expect-count (text-prefix "Row ") 9999)
    (expect-not-visible (text "Row 5000: 0"))))
