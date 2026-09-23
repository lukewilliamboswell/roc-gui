;; Drives the real window's own pointer over the Frames strip and the duration
;; distribution: hovering marks what is under the pointer and reads it out,
;; and the wheel zooms the strip. Each state is photographed for review
;; against wireframe W5.
(test "the window hovers and zooms the frame strip and the distribution"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-frames.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (settle)
    (expect-on-screen (role canvas :name "Frames"))
    (screenshot "frames")
    (pointer-move (role canvas :name "Frames") 400 120)
    (settle)
    (expect-visible (role canvas-item :name "Hovered column"))
    (screenshot "frames-hover" :region (role canvas :name "Frames") :pad 4)
    (wheel (role canvas :name "Frames") 400 120 0 -120)
    (await-task)
    (settle)
    (expect-visible (role button :name "Show every frame"))
    (screenshot "frames-zoomed" :region (role canvas :name "Frames") :pad 4)
    (pointer-leave (role canvas :name "Frames"))
    (settle)
    (expect-not-visible (role canvas-item :name "Hovered column"))
    (scroll (role scroll :name "Frames scroll") :to (role canvas :name "List passes"))
    (settle)
    (screenshot "frames-lists")
    (click (role button :name "Interactions"))
    (settle)
    (expect-on-screen (role canvas :name "Duration distribution"))
    (pointer-move (role canvas :name "Duration distribution") 57 80)
    (settle)
    (expect-visible (role canvas-item :name "Hovered bucket"))
    (screenshot "distribution-hover" :region (role canvas :name "Duration distribution") :pad 4)))
