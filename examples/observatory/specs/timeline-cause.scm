;; A frame pressed in the strip names the cycles its owner recorded it was the
;; first to draw. The first drawn frame draws the init cycle. The Timeline marks
;; that frame and its cycle, and the cycle opens in the inspector.
(test "a pressed frame shows the cycles it drew and opens one"
  (grants
    (directory "fixture/window"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-rows.rgstats"))
    (await-task)
    (click (role button :name "Frames"))
    (drag (role canvas :name "Frames") 57 120 57 120)
    (await-task)
    (expect-visible (text "FRAME r1 #0"))
    (expect-visible (within (role row :name "Frame cause") (text "first to draw 1 cycle(s):")))
    (expect-visible (role button :name "Cause r1 #0"))
    (click (role button :name "Timeline"))
    (await-task)
    (expect-visible (role canvas-item :name "Selected frame"))
    (expect-visible (role canvas-item :name "Linked cycle r1 #0"))
    (expect-visible (text-prefix "FRAME r1 #0 · host stages "))
    (click (role button :name "Cause r1 #0"))
    (await-task)
    (expect-visible (text "CYCLE r1 #0 · init · mount · interactive"))))
