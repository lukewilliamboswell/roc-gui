; Acting twice on the same frame, and scrubbing back and forth over recorded
; positions. A second keyframe at a frame replaces the first rather than
; stacking beside it, and each frame restores the position its keyframe holds.
(test "a keyframe is replaced in place and restores its position"
  (steps
    (click (role button :name "Select Title card"))
    (expect-visible (text "80, 70"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))
    ; Pressing again on the same frame replaces the keyframe, never stacks one.
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))
    ; Move the shape at a later frame and record where it landed.
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 10 of 120"))
    (drag (role canvas :name "Stage") 120 100 220 180)
    (expect-visible (text "Move committed"))
    (expect-visible (text "180, 150"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 2"))
    ; Moving again and re-recording replaces that frame's keyframe in place.
    (drag (role canvas :name "Stage") 220 180 270 180)
    (expect-visible (text "230, 150"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 2"))
    ; Scrubbing back restores the first frame's recorded position.
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 0 of 120"))
    (expect-visible (text "80, 70"))
    ; And forward again restores the replacement, not the position it replaced.
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 10 of 120"))
    (expect-visible (text "230, 150"))))
