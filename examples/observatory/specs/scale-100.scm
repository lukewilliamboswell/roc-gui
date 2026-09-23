;; The scaling case: opening a benchmark output folder of 100 real captures.
;; Listing opens every capture to read its identity and health.
(test "open a folder of 100 captures"
  (grants
    (directory "fixture/scale-100"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps
    (mark-metrics)
    (click (role button :name "Open folder"))
    (await-task)
    (expect-count (button-prefix "Capture ") 100)))
