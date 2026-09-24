;; A semantic-headless capture draws no GPUI frame, so the Frames view shows
;; the family's status and reason instead of a chart.
(test "the Frames view of a headless capture is not_recorded with its reason"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (expect-visible (text "Frames not_recorded: semantic headless execution draws no GPUI frame"))
    (expect-not-visible (role canvas :name "Frames"))
    (expect-not-visible (role column :name "Native work"))))
