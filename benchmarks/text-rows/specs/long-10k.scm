(test "Text rows: 10,000 long messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (mark-metrics) (click (role button :name "Show 10,000 long messages"))
    (expect-count (text-prefix "Message ") 10000)))
