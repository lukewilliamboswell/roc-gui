; The window before anything is open, and the return to that rest state. No
; folder means no filter, no rows, and no transform controls to press; and
; scanning again puts the viewer back to its invitation instead of leaving the
; previous folder's picture hanging there.
(test "the viewer rests empty before and after a scan"
  (grants
    (directory "fixture"))
  (steps
    (expect-visible (text "No folder open"))
    (expect-visible (text "Choose an image from the gallery"))
    (expect-not-visible (role textbox :name "Filter images"))
    (expect-not-visible (role virtual-list :name "Image thumbnails"))
    (expect-not-visible (role button :name "Fit image"))
    (expect-not-visible (role image :name "Selected image"))
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "27 of 27 entries"))
    ; Nothing is selected by the scan itself.
    (expect-visible (text "Choose an image from the gallery"))
    (click (role button :name "View image sunset.svg"))
    (expect-visible (role image :name "Selected image"))
    (expect-not-visible (text "Choose an image from the gallery"))
    ; Opening a folder again drops the selection with the scan it belonged to.
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "27 of 27 entries"))
    (expect-visible (text "Choose an image from the gallery"))
    (expect-not-visible (role image :name "Selected image"))))
