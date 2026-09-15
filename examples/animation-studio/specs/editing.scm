(test "create, move, undo, and redo shapes through the canvas"
  (steps
    (expect-visible (role canvas :name "Stage"))
    (expect-visible (role canvas-item :name "Title card"))
    (click (role button :name "Add rectangle"))
    (expect-visible (text "Layers: 3"))
    (expect-visible (role canvas-item :name "Rectangle 3"))
    (drag (role canvas :name "Stage") 150 130 230 190)
    (expect-visible (text "Move committed"))
    (click (role button :name "Undo"))
    (expect-visible (text "Undid edit"))
    (click (role button :name "Redo"))
    (expect-visible (text "Redid edit"))))
