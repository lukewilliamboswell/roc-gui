(test "Text rows: 100 metadata-rich messages"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps (mark-metrics) (click (role button :name "Show 100 metadata-rich messages"))
    (expect-patch :kind replace :staged 621 :removed 21)
    (expect-count (text-prefix "Message ") 100)
    (expect-count (text "Status: Delivered") 100)))
