; Reversing every viewer transform. The control that is in force says so rather
; than a separate line repeating it, a second press of the same one is not a
; toggle, and grayscale goes back off again without disturbing the fit.
;
; The accessible name is what is asserted here because it is what a person using
; a screen reader is given: the platform's action button has no pressed state,
; so the fill alone would leave that person with three identical controls.
(test "viewer transforms reverse and repeat"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Open image folder"))
    (await-task)
    (click (role button :name "View image sunset.svg"))
    (expect-visible (role button :name "Fit image, current view"))
    (expect-not-visible (role button :name "Fit image"))
    (click (role button :name "Fill image bounds"))
    (expect-visible (role button :name "Fill image bounds, current view"))
    ; Selecting one view releases the one that was in force.
    (expect-visible (role button :name "Fit image"))
    (click (role button :name "Show actual image size"))
    (expect-visible (role button :name "Show actual image size, current view"))
    ; Pressing the same control twice keeps the mode it names.
    (click (role button :name "Show actual image size, current view"))
    (expect-visible (role button :name "Show actual image size, current view"))
    (click (role button :name "Fit image"))
    (expect-visible (role button :name "Fit image, current view"))
    (click (role checkbox :name "Grayscale preview"))
    (click (role checkbox :name "Grayscale preview"))
    (expect-visible (role button :name "Fit image, current view"))
    (expect-visible (role image :name "Selected image"))
    ; The picture is unchanged by any of it: same bytes, same metadata.
    (expect-image-bytes (role image :name "Selected image") 396)
    (expect-visible (text "320 × 180 pixels; 396 encoded bytes"))))
