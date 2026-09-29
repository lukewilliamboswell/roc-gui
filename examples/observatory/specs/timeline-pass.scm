;; A list pass on the Timeline opens what its recorder linked it to. The
;; capture's first pass is the paint that settled the list's first rows, so
;; pressing it selects the frame that painted it, and the Timeline marks that
;; frame. Passes are named by their order on the clock, which a regenerated
;; fixture keeps, rather than by the column its timing puts them in.
(test "a pressed list pass opens the frame that painted it"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-rows.rgstats"))
    (await-task)
    (click (role button :name "Timeline"))
    (await-task)
    (expect-not-visible (role canvas-item :name "Selected frame"))
    (click (role canvas-item :name "List pass 1"))
    (await-task)
    (expect-visible (role canvas-item :name "Selected frame"))
    (expect-visible (text-prefix "FRAME r1 #"))))
