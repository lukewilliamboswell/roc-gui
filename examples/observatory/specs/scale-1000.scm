;; The scaling case: opening a benchmark output folder of 1000 real captures.
;; Listing opens every capture to read its identity and health.
(test "open a folder of 1000 captures"
  (grants
    (directory "fixture/scale-1000"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps
    (mark-metrics)
    (click (role button :name "Open folder"))
    (await-task)
    (expect-count (button-prefix "Capture ") 1000)))
