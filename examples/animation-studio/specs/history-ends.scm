; The ends of the history. Nothing has been edited yet, so the first press of
; Undo must do nothing at all; and once history exists, a fresh edit made after
; an undo discards the redo that is no longer reachable.
(test "undo and redo stop at the ends of the history"
  (steps
    (expect-visible (text "Ready"))
    ; Undo and Redo are disabled at rest, so the first press changes nothing.
    (click (role button :name "Undo"))
    (click (role button :name "Redo"))
    (expect-visible (text "Ready"))
    (expect-visible (text "LAYERS (2)"))
    (click (role button :name "Add rectangle"))
    (expect-visible (text "LAYERS (3)"))
    (click (role button :name "Undo"))
    (expect-visible (text "Undid edit"))
    (expect-visible (text "LAYERS (2)"))
    ; The history is empty again, so a second Undo cannot remove a layer.
    (click (role button :name "Undo"))
    (expect-visible (text "LAYERS (2)"))
    ; A new edit made instead of the redo discards the redone future.
    (click (role button :name "Add ellipse"))
    (expect-visible (text "LAYERS (3)"))
    (expect-visible (role canvas-item :name "Layer 4"))
    (click (role button :name "Redo"))
    (expect-visible (text "LAYERS (3)"))
    (expect-not-visible (role canvas-item :name "Layer 3"))))
