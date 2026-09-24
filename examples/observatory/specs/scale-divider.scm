;; The scaling case for the split: the inspector's divider dragged beside a
;; session of 10,000 cycles. The inspector's size is the window's own state,
;; so a drag renders the window alone and compares, rather than builds, every
;; view beside it; the cycle list keeps its rows, whatever its length.
(test "drag the inspector divider beside a session of 10000 cycles"
  (grants
    (directory "fixture/session"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-session.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (expect-rows (role virtual-list :name "Cycles") :count 10000 :first 0 :mounted 70)
    (mark-metrics)
    (drag (role separator :name "Inspector divider") 2 300 -98 300)
    (expect-value (role separator :name "Inspector divider") "460")
    (expect-component-work :rendered 1 :skipped 7 :mounted 0 :retired 0)
    (expect-rows (role virtual-list :name "Cycles") :count 10000 :first 0 :mounted 70)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")) 70)))
