; The cover is a photograph, too large to pay for in executable size, so it is
; read from the asset set the application ships with rather than imported at
; compile time. The store's manifest must agree before the store opens at all.
; One open, one manifest check, one read, nothing refused, and the exact encoded
; size of the one asset that was read.
(test "the shipped cover is read from the asset store"
  (grants
    (directory "library")
    (audio null)
    (assets "assets"))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (expect-visible (text "5 tracks"))
    (expect-visible (role image :name "Cover art"))
    ;; The same count on both sides ties the bytes the store read to the bytes
    ;; the sleeve is drawing: one asset, one image node, no copy in between.
    (expect-image-bytes (role image :name "Cover art") 142534)
    (expect-not-visible (text "Cover art unavailable"))
    (expect-asset-counters 1 0 1 1 0 142534)))
