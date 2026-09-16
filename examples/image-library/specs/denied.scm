; The first run of a folder browser that is never given a folder. Every other
; specification here grants one, so without this the refusal path — the one an
; ordinary person meets by pressing Cancel or by saying no — was never rendered
; at all.
;
; A refusal must say what happened, what it means for what is already on screen,
; and what to do next, and the retry must actually work: pressing Open folder
; again clears the band rather than leaving a person to wonder whether the
; second press did anything.
(test "a refused folder is a state the application explains"
  (grants)
  (steps
    (expect-visible (text "No folder open"))
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "No folder was opened"))
    (expect-visible (text "Access to a folder was not granted, so nothing was read. Nothing already open has changed. Press Open folder to choose again."))
    ; Nothing was invented in place of the folder: no gallery, no viewer, and no
    ; directory was listed or read behind the refusal.
    (expect-not-visible (role virtual-list :name "Image thumbnails"))
    (expect-not-visible (role image :name "Selected image"))
    (expect-visible (text "Choose an image from the gallery"))
    (expect-file-picks 1)
    (expect-file-lists 0)
    (expect-file-reads 0)
    ; The same refusal twice reads the same way rather than stacking up.
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "No folder was opened"))
    (expect-count (text "No folder was opened") 1)
    (expect-file-picks 2)))
