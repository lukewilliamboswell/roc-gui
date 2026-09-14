(test "Text rows: 1,000 metadata-rich messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps (mark-metrics) (click (role button :name "Show 1,000 metadata-rich messages"))
    (expect-count (text-prefix "Message ") 1000)
    (expect-count (text "Status: Delivered") 1000)))
