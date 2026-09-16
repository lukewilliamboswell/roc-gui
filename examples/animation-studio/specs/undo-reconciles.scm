; Undoing back past the layer you were standing on. The selection has to go
; with it: a selection pointing at a shape the restored document no longer
; contains leaves the inspector empty while Add keyframe does nothing at all and
; says nothing about why — a dead control with no explanation.
;
; Redoing brings the layer back, and the selection does not come back with it,
; because a person who pressed Redo asked for their document, not for their
; cursor to be put somewhere they did not put it.
(test "undo takes the selection with the layer it removes"
  (steps
    (click (role button :name "Add rectangle"))
    (expect-visible (text "LAYERS (3)"))
    ; The new layer is selected, so the inspector is showing it.
    (expect-visible (text "Layer 3"))
    (expect-visible (text "Keyframes in document: 0"))
    (click (role button :name "Undo"))
    (expect-visible (text "LAYERS (2)"))
    ; The layer is gone and so is the selection, rather than the inspector
    ; sitting on a shape that no longer exists.
    (expect-visible (text "No layer selected"))
    (expect-visible (text "Select a layer or press a shape on the stage."))
    ; Add keyframe now says what is missing instead of silently doing nothing.
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Select a shape before adding a keyframe"))
    (expect-visible (text "Keyframes in document: 0"))
    ; Selecting a layer that does exist works, and recording works again.
    (click (role button :name "Select Accent"))
    (click (role button :name "Add keyframe"))
    (expect-visible (text "Keyframes in document: 1"))))
