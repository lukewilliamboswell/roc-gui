(test "Text rows: 100 short messages"
  (benchmark :warmups 2 :samples 31 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (mark-metrics) (click (role button :name "Show 100 short messages"))
    (expect-patch :kind replace :staged 312 :removed 12)
    (expect-count (text-prefix "Message ") 100)))
