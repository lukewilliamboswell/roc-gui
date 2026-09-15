; A folder that holds only files, with files hidden, says so instead of
; presenting an empty panel.
(test "Folder browser names an empty result"
  (steps
    (settle)
    (click (role button :name "Choose directory"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Entry readme.txt"))
    (click (role checkbox :name "Show files as well as folders"))
    (settle)
    (expect-on-screen (text "No folders here"))
    (screenshot "files-hidden")))
