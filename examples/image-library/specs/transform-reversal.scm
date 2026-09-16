; Reversing every viewer transform. Each fit control names the mode it selects,
; a second press of the same one is not a toggle, and grayscale goes back off
; again without disturbing the fit.
(test "viewer transforms reverse and repeat"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Open image folder"))
    (await-task)
    (click (role button :name "View image sunset.svg"))
    (expect-visible (text "View: Fit"))
    (click (role button :name "Fill image bounds"))
    (expect-visible (text "View: Crop to fill"))
    (click (role button :name "Show actual image size"))
    (expect-visible (text "View: Actual size"))
    ; Pressing the same control twice keeps the mode it names.
    (click (role button :name "Show actual image size"))
    (expect-visible (text "View: Actual size"))
    (click (role button :name "Fit image"))
    (expect-visible (text "View: Fit"))
    (click (role checkbox :name "Grayscale preview"))
    (click (role checkbox :name "Grayscale preview"))
    (expect-visible (text "View: Fit"))
    (expect-visible (role image :name "Selected image"))
    ; The picture is unchanged by any of it: same bytes, same metadata.
    (expect-image-bytes (role image :name "Selected image") 396)
    (expect-visible (text "320 × 180 pixels; 396 encoded bytes"))))
