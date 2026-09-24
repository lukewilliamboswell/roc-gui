;; The Timeline's scaling case: the window session of at least 1,000 drawn
;; frames and as many list passes. Each lane keeps one mark per column, the
;; longest cycle, costliest frame, or largest pass, so the whole session draws
;; no more marks than a short one. The wheel reads a narrower span of the clock
;; around the pointer, and the whole session is one press away.
(test "the Timeline draws a session of 1000 frames and zooms into it"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-frames.rgstats"))
    (await-task)
    (click (role button :name "Timeline"))
    (await-task)
    (expect-visible (role canvas :name "Timeline"))
    (expect-visible (canvas-item-prefix "Frame r1 #"))
    (expect-not-visible (role button :name "Show the whole timeline"))
    (wheel (role canvas :name "Timeline") 456 120 0 -120)
    (await-task)
    (expect-not-visible (role panel :name "Capture error"))
    (expect-visible (role button :name "Show the whole timeline"))
    (wheel (role canvas :name "Timeline") 456 120 0 -120)
    (await-task)
    (wheel (role canvas :name "Timeline") 456 120 120 0)
    (await-task)
    (expect-not-visible (role panel :name "Capture error"))
    (click (role button :name "Show the whole timeline"))
    (await-task)
    (expect-not-visible (role button :name "Show the whole timeline"))
    (expect-visible (canvas-item-prefix "Frame r1 #"))))
