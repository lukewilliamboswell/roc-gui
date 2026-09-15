(test "surface unsupported and corrupt files without blocking the gallery"
  (steps
    (click (role button :name "Open image folder"))
    (await-task)
    (replace-text (role textbox :name "Filter images") "notes.txt")
    (expect-visible (text "notes.txt — Unsupported format"))
    (replace-text (role textbox :name "Filter images") "corrupt.svg")
    (expect-visible (text "corrupt.svg — Corrupt image"))
    (replace-text (role textbox :name "Filter images") "collection-")
    (expect-visible (text "24 of 27 entries"))
    (expect-visible (role virtual-list :name "Image thumbnails"))))
