;; Drives the real window's own pointer over the Timeline: hovering marks what
;; is under the pointer and reads it out, and the wheel zooms around it. Each
;; state is photographed for review against wireframe W6.
(test "the window hovers and zooms the Timeline"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-rows.rgstats"))
    (await-task)
    (click (role button :name "Timeline"))
    (await-task)
    (settle)
    (expect-on-screen (role canvas :name "Timeline"))
    (screenshot "timeline")
    (pointer-move (role canvas :name "Timeline") 100 75)
    (settle)
    (expect-visible (role canvas-item :name "Hovered mark"))
    (screenshot "timeline-hover" :region (role canvas :name "Timeline") :pad 4)
    (wheel (role canvas :name "Timeline") 100 75 0 -120)
    (await-task)
    (settle)
    (expect-visible (role button :name "Show the whole timeline"))
    (screenshot "timeline-zoomed" :region (role canvas :name "Timeline") :pad 4)
    (pointer-leave (role canvas :name "Timeline"))
    (settle)
    (expect-not-visible (role canvas-item :name "Hovered mark"))))
