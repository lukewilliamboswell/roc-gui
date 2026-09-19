; Moving a shape is recorded against the frame it was moved on. Once a shape is
; keyed, every frame's position is a function of its keys, so a drag that
; changed only the shape's one stored position was thrown away by the next
; scrub — the shape looked moved until the timeline was touched, and then
; snapped back. That is the "position is global" complaint: with keys in the
; document, there is no one position left for a drag to mean.
;
; Every shape, not only one that has already been keyed. Making a drag record a
; key only for keyed shapes meant two shapes that look alike behaved
; differently depending on whether someone had happened to press Add keyframe
; on one of them earlier, with nothing on the stage saying which was which: the
; rectangle animated and the ellipse beside it silently would not. A shape's
; first key is also its only key, and one key is a constant position at every
; frame, so a static layout pays nothing for this but a marker on the timeline.
(test "moving a shape records it at the frame it was moved on"
  (steps
    (click (role button :name "Select Title card"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))
    ; Move it at frame 30. That is a key at frame 30.
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
    ; A shape nobody has keyed records its first key from the move itself, so it
    ; behaves the same way from the first drag rather than from the first press
    ; of Add keyframe.
    (click (role button :name "Select Accent"))
    (expect-visible (text "380, 160"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 20 of 120"))
    (drag (role canvas :name "Stage") 450 230 550 330)
    (expect-visible (text "480, 260"))
    (expect-visible (text "Keyframes in document: 3"))
    ; One key is a constant position, so it is at 480, 260 everywhere — the
    ; ellipse has not been made to jump by being moved once.
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 0 of 120"))
    (expect-visible (text "480, 260"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 60 of 120"))
    (expect-visible (text "480, 260"))))
