(test "Text rows: 10,000 metadata-rich messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 0 :change-size 10000)
  (steps (mark-metrics) (click (role button :name "Show 10,000 metadata-rich messages"))
    (expect-patch :kind replace :staged 60012 :removed 12)
    (expect-count (text-prefix "Message ") 10000)
    (expect-count (text "Status: Delivered") 10000)))
