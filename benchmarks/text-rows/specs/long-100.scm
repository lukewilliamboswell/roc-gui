(test "Text rows: 100 long messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (mark-metrics) (click (role button :name "Show 100 long messages"))
    (expect-patch :kind replace :staged 312 :removed 12)
    (expect-count (text-prefix "Message ") 100)))
