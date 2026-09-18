; What a keyframe is for. Two keys forty frames apart describe a movement, and
; the frames between them are where that movement happens. Taking the last key
; at or before the frame made the shape hold still for forty frames and then
; jump, which is not the motion anyone recorded: playing it back showed a pose
; that never matched where the shape had been moved to until the instant it
; snapped there.
;
; The last two steps are the same defect seen from the other end. Before a
; shape's first key there was no key to take, so the position was left at
; whatever the previously applied frame had written into the document. Playback
; wraps from the last frame back to zero, so every loop started where the
; previous one ended and the animation drifted. A frame is a pure function of
; the keys and the frame number, so returning to frame 0 must return the shape
; to where frame 0 puts it, whatever the document was carrying on the way past.
(test "frames between two keys hold the movement between them"
  (steps
    (click (role button :name "Select Title card"))
    ; A key at frame 0, where the shape already is.
    (expect-visible (text "80, 70"))
    (click (role button :name "Add keyframe"))
    ; And a key at frame 40, two hundred pixels along and two hundred down.
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 40 of 120"))
    (drag (role canvas :name "Stage") 120 100 320 300)
    (expect-visible (text "280, 270"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 2"))
    ; Past the last key the last key holds: there is nothing to move towards.
    (click (role button :name "Scrub forward"))
    (expect-visible (text "Frame 50 of 120"))
    (expect-visible (text "280, 270"))
    ; Three quarters of the way along is three quarters of the movement.
    (click (role button :name "Scrub backward"))
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 30 of 120"))
    (expect-visible (text "230, 220"))
    ; Halfway is halfway, and not still at the start.
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 20 of 120"))
    (expect-visible (text "180, 170"))
    ; A quarter of the way is a quarter of the way.
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 10 of 120"))
    (expect-visible (text "130, 120"))
    ; And the first key's own frame is the first key's pose.
    (click (role button :name "Scrub backward"))
    (expect-visible (text "Frame 0 of 120"))
    (expect-visible (text "80, 70"))))
