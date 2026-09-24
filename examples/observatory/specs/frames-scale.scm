;; The Frames view's scaling case: one window session of at least 1,000 drawn
;; frames, several times the strip's columns. The strip always draws 240 columns, each the costliest of the frames
;; it stands for, so a slow frame is never averaged away. Scrolling the wheel
;; over the strip reads a narrower span around the pointer, and the whole
;; capture is one press away.
(test "the frame strip draws a session of 1000 frames and zooms into it"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-frames.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (expect-count (canvas-item-prefix "Frame r1 #") 240)
    (expect-not-visible (role button :name "Show every frame"))
    (wheel (role canvas :name "Frames") 416 100 0 -120)
    (await-task)
    (expect-count (canvas-item-prefix "Frame r1 #") 240)
    (expect-not-visible (role panel :name "Capture error"))
    (expect-visible (role button :name "Show every frame"))
    (wheel (role canvas :name "Frames") 416 100 0 -120)
    (await-task)
    (expect-count (canvas-item-prefix "Frame r1 #") 240)
    (click (role button :name "Show every frame"))
    (await-task)
    (expect-not-visible (role button :name "Show every frame"))
    (expect-count (canvas-item-prefix "Frame r1 #") 240)))
