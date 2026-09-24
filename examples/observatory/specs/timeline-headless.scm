;; A semantic-headless capture still records every cycle's interval, so the
;; Timeline draws its cycles. It draws no frame and has no viewport, so the
;; frame and list lanes say so with their families' reasons, and a frame's
;; cause is not recorded.
(test "the Timeline of a headless capture draws its cycles and says frames were not recorded"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Timeline"))
    (await-task)
    (expect-visible (role canvas :name "Timeline"))
    (expect-visible (canvas-item-prefix "Cycle r"))
    (expect-not-visible (canvas-item-prefix "Frame r"))
    (expect-value (role canvas-item :name "Reason frames") "gpui_frame_spans not_recorded: semantic headless execution draws no GPUI frame")
    (expect-value (role canvas-item :name "Reason lists") "virtual_list_materialization not_recorded: semantic headless execution has no viewport")
    (expect-visible (within (role row :name "Linkage frame_cycle_linkage") (text "frame_cycle_linkage not_recorded: semantic headless execution draws no GPUI frame")))
    (expect-visible (within (role row :name "Linkage virtual_list_linkage") (text "virtual_list_linkage not_recorded: semantic headless execution has no viewport")))))
