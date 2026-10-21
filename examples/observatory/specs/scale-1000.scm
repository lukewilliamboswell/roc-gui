;; The scaling case: opening a benchmark output folder of 1000 real captures.
;; Every name is listed at once with the first page of 64 captures summarized,
;; so the folder shows in the time a page takes; the rest are summarized a page
;; at a time on a worker, and the heading counts them in.
(test "open a folder of 1000 captures"
  (grants
    (directory "fixture/scale-1000"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps
    (mark-metrics)
    (click (role button :name "Open folder"))
    (await-task)
    ; only the rows a screen shows, and one screen below, are built
    (expect-rows (role virtual-list :name "Captures") :count 1000 :first 0 :mounted 70)
    (expect-count (button-prefix "Capture ") 70)
    (expect-visible (text "CAPTURES IN scale-1000 · 1000 · read 64 of 1000"))
    (await-count (text "CAPTURES IN scale-1000 · 1000") 1)
    (expect-count (text "… reading") 0)))
