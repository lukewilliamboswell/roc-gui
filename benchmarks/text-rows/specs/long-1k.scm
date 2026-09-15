(test "Text rows: 1,000 long messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (mark-metrics) (click (role button :name "Show 1,000 long messages"))
    (expect-patch :kind replace :staged 3012 :removed 12)
    (expect-count (text-prefix "Message ") 1000)))
