; Recording keyframes out of order, which is what a person does the moment they
; go back to fix an earlier pose. A frame past both keys must hold the later
; key, not the one that happened to be typed last.
;
; This is the shape of a real bug: the keyframes were appended in the order they
; were recorded, and the frame was applied by taking the last key at or before
; it. Record frame 40 and then frame 10 and the frame-10 pose won everywhere
; past frame 40, so going back to adjust an opening pose silently rewrote the
; whole rest of the timeline.
(test "a keyframe recorded out of order does not outrank a later one"
  (steps
    (click (role button :name "Select Title card"))
    (expect-visible (text "80, 70"))
    ; Frame 40 first: move the shape and record where it landed.
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 40 of 120"))
    (drag (role canvas :name "Stage") 120 100 320 300)
    (expect-visible (text "280, 270"))
    (click (role button :name "Add keyframe"))
    ; Then go back to frame 10 and record a different pose there.
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 10 of 120"))
    (drag (role canvas :name "Stage") 320 300 220 200)
    (expect-visible (text "180, 170"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 2"))
    ; Now scrub past both. Frame 40's pose is the one in force, because it is
    ; the later frame — not because it was recorded first or last.
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 60 of 120"))
    (expect-visible (text "280, 270"))
    ; And between them, frame 10's pose still holds.
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 20 of 120"))
    (expect-visible (text "180, 170"))))
