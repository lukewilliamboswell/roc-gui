(test "reject unsupported image"
  (steps
    (click (role button :name "Choose image folder"))
    (await-task)
    (click (role button :name "Open image notes.txt"))
    (expect-visible (role panel :name "Image error"))
    (expect-visible (text "Unsupported image format"))))
