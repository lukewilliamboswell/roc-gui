;; A window capture on its one clock: a lane of cycles for each trigger, the
;; drawn frames, and the virtual-list passes, with the recorder's linkage
;; families beside them. The init cycle starts the clock, so it is the first
;; mark of its lane: hovering it marks it, the wheel zooms around it, and
;; pressing it opens it in the inspector.
(test "the Timeline lays a window capture's cycles, frames, and list passes on one clock"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-rows.rgstats"))
    (await-task)
    (click (role button :name "Timeline"))
    (await-task)
    (expect-visible (role canvas :name "Timeline"))
    (expect-value (role canvas-item :name "Lane cycles click") "cycles click")
    (expect-value (role canvas-item :name "Lane cycles init") "cycles init")
    (expect-value (role canvas-item :name "Lane cycles viewport") "cycles viewport")
    (expect-value (role canvas-item :name "Lane frames") "frames")
    (expect-value (role canvas-item :name "Lane lists") "lists")
    (expect-value (role canvas-item :name "Window start") "0.000 ms")
    (expect-value (role canvas-item :name "Timeline readout") "Hover a mark for its detail; press a frame for the cycles it drew, or a cycle to inspect it; scroll to zoom.")
    (expect-visible (role canvas-item :name "Cycle r1 #0"))
    (expect-visible (canvas-item-prefix "Frame r1 #"))
    (expect-visible (canvas-item-prefix "List "))
    (expect-not-visible (role canvas-item :name "Reason frames"))
    (expect-not-visible (role canvas-item :name "Reason lists"))
    (expect-visible (within (role row :name "Linkage frame_cycle_linkage") (text "frame_cycle_linkage complete: every drawn frame records the cycles it was first to draw")))
    (expect-visible (within (role row :name "Linkage virtual_list_linkage") (text "virtual_list_linkage complete: every list pass records the frame or cycle that produced it")))
    (expect-visible (text "Press a frame to see the cycles it was the first to draw."))
    ; The init lane is the second, and the init cycle begins at the gutter.
    (pointer-move (role canvas :name "Timeline") 100 75)
    (expect-visible (role canvas-item :name "Hovered mark"))
    (pointer-leave (role canvas :name "Timeline"))
    (expect-not-visible (role canvas-item :name "Hovered mark"))
    (expect-not-visible (role button :name "Show the whole timeline"))
    (wheel (role canvas :name "Timeline") 100 75 0 -120)
    (await-task)
    (expect-visible (role button :name "Show the whole timeline"))
    (expect-visible (role canvas-item :name "Cycle r1 #0"))
    (click (role button :name "Show the whole timeline"))
    (await-task)
    (expect-not-visible (role button :name "Show the whole timeline"))
    (drag (role canvas :name "Timeline") 100 75 100 75)
    (await-task)
    (expect-visible (text "CYCLE r1 #0 · init · mount · interactive"))
    (expect-visible (role row :name "Waterfall cycle"))))
