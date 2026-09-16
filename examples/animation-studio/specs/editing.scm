; The ordinary editing loop, and the two places it used to lie about itself: a
; press that only selects is not an edit and must leave Undo alone, and a
; release that followed no movement must not report a move.
(test "create, select, move, undo, and redo shapes"
  (steps
    (expect-visible (role canvas :name "Stage"))
    (expect-visible (role canvas-item :name "Title card"))
    (click (role button :name "Add rectangle"))
    (expect-visible (text "LAYERS (3)"))
    (expect-visible (role canvas-item :name "Layer 3"))
    (click (role button :name "Select Title card"))
    (expect-visible (text "Selected Title card"))
    (click (role button :name "Select Layer 3"))
    (expect-visible (text "Selected Layer 3"))
    ; Pressing and releasing on bare canvas deselects and changes nothing, so
    ; it does not claim to have committed a move.
    (drag (role canvas :name "Stage") 620 420 620 420)
    (expect-visible (text "Canvas selected"))
    (expect-not-visible (text "Move committed"))
    ; A real drag of a real shape does commit, and the inspector agrees.
    (drag (role canvas :name "Stage") 420 180 500 240)
    (expect-visible (text "Move committed"))
    (expect-visible (text "460, 206"))
    (click (role button :name "Undo"))
    (expect-visible (text "Undid edit"))
    ; Undo puts the shape back where the gesture found it, not somewhere in the
    ; middle of it: the snapshot is the document as it stood before the move.
    (expect-visible (text "380, 146"))
    (click (role button :name "Redo"))
    (expect-visible (text "Redid edit"))
    (expect-visible (text "460, 206"))))
