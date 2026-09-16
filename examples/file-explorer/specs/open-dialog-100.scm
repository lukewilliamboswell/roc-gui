(test "open close-directory dialog over 100 entries"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 2 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Open project"))
    (await-task)
	(expect-file-picks 1) (expect-file-lists 1) (expect-file-opens 0) (expect-file-reads 0)
    (mark-metrics)
    (click (role button :name "Close directory"))
    (expect-visible (role dialog :name "Close directory confirmation"))
    (expect-count (button-prefix "Select ") 100)))
