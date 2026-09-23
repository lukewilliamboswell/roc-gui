;; The scaling case for a watched folder: a benchmark output folder of 100 real
;; captures, one of which is replaced while the folder is open. The folder's
;; watch names the one capture that changed, so only that capture is read again
;; and every other listing is kept: one more connection is opened, not a
;; hundred.
(test "a changed capture in a folder of 100 is the only one read again"
  (grants
    (directory copy "fixture/scale-100"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (expect-sqlite-counters 0 100 200)
    (expect-visible (within (role row :name "Capture row run-0002.rgstats") (text "database-browser")))
    (replace-file "run-0002.rgstats" "fixture/captures/counter-counting.rgstats")
    ; The watch reports the capture's name, and the folder is listed again.
    (await-task)
    (await-task)
    (expect-sqlite-counters 0 101 202)
    (expect-visible (within (role row :name "Capture row run-0002.rgstats") (text "counter")))
    (expect-count (button-prefix "Capture run-") 70)
    (expect-watch-counters 1 _ 0 0 1)))
