;; A cycle near the end of a long session opens its step, ten thousand steps
;; into the run: the step list reads the page around the step and scrolls to
;; it, without reading or building the steps before it.
(test "a late cycle of a long session opens its step in place"
  (grants
    (directory "fixture/session"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-session.rgstats"))
    (await-task)
    (click (role button :name "Interactions"))
    (click (role button :name "Filter input replace"))
    (await-task)
    (expect-count (within (role virtual-list :name "Cycles") (button-prefix "Cycle r1 ")) 2)
    (click (role button :name "Cycle r1 #9998"))
    (await-task)
    (click (role button :name "Show step"))
    (await-task)
    (expect-visible (text "STEPS OF RUN 1 · 10001"))
    (expect-visible (within (role panel :name "Focused step") (text-prefix "line 10004 · replace-text")))
    (expect-rows (role virtual-list :name "Steps") :count 10001 :first 9931)
    (expect-count (within (role virtual-list :name "Steps") (text "Step line 10004")) 1)
    (expect-count (within (role virtual-list :name "Steps") (text "Step line 12")) 0)
    (expect-count (within (role virtual-list :name "Steps") (text "reading")) 0)))
