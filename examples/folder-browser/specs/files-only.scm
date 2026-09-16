; A folder that holds only files, seen through the checkbox that hides them.
; The empty result has to name itself, and ticking the box back has to restore
; the rows rather than leaving the notice behind.
(test "A folder of only files names its empty result and gives the rows back"
  (grants
    (directory "files-only-fixture"))
  (steps
    (click (role button :name "Choose directory"))
    (await-task)
    (expect-visible (role scroll :name "Directory contents"))
    (expect-visible (text "readme.txt"))
    (expect-visible (text "notes.txt"))
    (expect-visible (text "0 folders · 2 files"))
    (click (role checkbox :name "Show files as well as folders"))
    (expect-visible (text "No folders here"))
    ; the counts keep reporting what is there, and say the files are hidden
    (expect-visible (text "0 folders · 2 files hidden"))
    (expect-not-visible (text "readme.txt"))
    (expect-not-visible (role scroll :name "Directory contents"))
    (click (role checkbox :name "Show files as well as folders"))
    (expect-visible (text "readme.txt"))
    (expect-visible (text "0 folders · 2 files"))
    (expect-not-visible (text "No folders here"))
    (expect-visible (role scroll :name "Directory contents"))))
