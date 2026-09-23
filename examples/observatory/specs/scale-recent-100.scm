;; The recent list's scaling case: a start page remembering a benchmark
;; folder's 100 captures. Reopening the most recent opens it, remembers it
;; again, and reads the list, the host checking every entry against what is
;; at its place; only the rows near the list's viewport are built. The list is
;; the host's, so it outlives each benchmark lifecycle, and reopening leaves it
;; as it found it.
(test "reopen one of 100 recent captures"
  (grants
    (recents (each "fixture/scale-100" "rgstats")))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 100 :change-size 0)
  (steps
    (expect-rows (role virtual-list :name "Recent") :count 100 :first 0)
    (mark-metrics)
    (click (role button :name "Recent run-0000.rgstats"))
    (await-task)
    (expect-selected (role tab :name "run-0000.rgstats"))
    (click (role button :name "Back to captures"))
    (expect-rows (role virtual-list :name "Recent") :count 100 :first 0)
    (expect-before (role button :name "Recent run-0000.rgstats") (role button :name "Recent run-0001.rgstats"))))
