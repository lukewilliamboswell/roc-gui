(test "open close-directory dialog over 100 entries"
  (benchmark :warmups 1 :samples 3 :iterations 2 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Choose directory"))
    (await-task)
    (mark-metrics)
    (click (role button :name "Close directory"))
    (expect-visible (role dialog :name "Close directory confirmation"))
    (expect-count (text-prefix "Entry: ") 100)))
