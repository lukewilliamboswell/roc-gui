; The two entries that cannot be decoded each stage the 512-byte glyph that
; stands in for the picture they do not have, so the owner's staged-node and
; staged-byte totals count them alongside the thumbnails.
(test "browse and transform a capability-scoped image"
  (grants
    (directory "fixture"))
  (steps
    (expect-image-owner-counters 0 0 0 0)
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-file-picks 1)
    (expect-file-lists 1)
    (expect-file-reads 26)
    (expect-visible (text "27 of 27 entries"))
    (expect-image-owner-counters 27 6668 26 1)
    (replace-text (role textbox :name "Filter images") "corrupt.svg")
    (expect-visible (text "corrupt.svg — Corrupt image"))
    (replace-text (role textbox :name "Filter images") "sunset.svg")
    (click (role button :name "View image sunset.svg"))
    (expect-visible (role image :name "Selected image"))
    (expect-image-bytes (role image :name "Selected image") 396)
    (expect-visible (text "320 × 180 pixels; 396 encoded bytes"))
    (expect-image-owner-counters 31 8368 26 1)
    (click (role button :name "Show actual image size"))
    (expect-visible (text "View: Actual size"))))
