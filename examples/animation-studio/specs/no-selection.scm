; The first press on an empty stage. Pressing bare canvas deselects, and from
; that rest state Add keyframe has to say what is missing rather than quietly
; recording nothing or acting on the shape that used to be selected.
(test "keyframing asks for a selection instead of guessing one"
  (steps
    (expect-visible (text "Ready"))
    (expect-visible (text "Title card"))
    ; Pressing the canvas away from every shape deselects.
    (drag (role canvas :name "Stage") 600 400 600 400)
    (expect-visible (text "No layer selected"))
    (expect-visible (text "Select a layer or press a shape on the stage."))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Select a shape before adding a keyframe"))
    (expect-visible (text "Keyframes in document: 0"))
    (expect-not-visible (role canvas-item :name "Keyframe 0"))
    ; Selecting again reverses the deselection, and the same press now records.
    (click (role button :name "Select Accent"))
    (expect-visible (text "Selected Accent"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))
    (expect-visible (role canvas-item :name "Keyframe 0"))))
