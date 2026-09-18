; Moving a shape that has keyframes has to be recorded against the frame it was
; moved on, or it is not a move at all. Once a shape is keyed, every frame's
; position is a function of its keys, so a drag that changed only the shape's
; one stored position was thrown away by the next scrub — the shape looked
; moved until the timeline was touched, and then snapped back. That is the
; "position is global" complaint: with keys in the document, there is no one
; position left for a drag to mean.
(test "moving a keyed shape records it at the frame it was moved on"
  (steps
    (click (role button :name "Select Title card"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))
    ; Move it at frame 30. The shape is keyed, so this is a key at frame 30.
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 30 of 120"))
    (drag (role canvas :name "Stage") 120 100 320 300)
    (expect-visible (text "280, 270"))
    (expect-visible (text "Keyframes in document: 2"))
    ; Leaving the frame and coming back finds the shape where it was left.
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 40 of 120"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 30 of 120"))
    (expect-visible (text "280, 270"))
    ; And frame 0 still holds its own key, untouched by a move made elsewhere.
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 0 of 120"))
    (expect-visible (text "80, 70"))
    ; A shape with no keys of its own is a static layout object: moving it moves
    ; it, and records nothing, because there is no animation to record against.
    (click (role button :name "Select Accent"))
    (expect-visible (text "380, 160"))
    (drag (role canvas :name "Stage") 450 230 470 250)
    (expect-visible (text "400, 180"))
    (expect-visible (text "Keyframes in document: 2"))))
