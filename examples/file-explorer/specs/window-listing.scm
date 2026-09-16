; Photographs the listing in a real window. Every row opens with the drawn kind
; of its entry, so a directory reads as a shape before any of its names are
; read, and the folders stay distinguishable from the files at a glance.
(test "File explorer draws the kind of every entry"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (screenshot "empty")
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Folder entry nested"))
    (expect-on-screen (role row :name "File entry alpha.txt"))
    (screenshot "listing")
    (screenshot "folder-row" :region (role row :name "Folder entry nested") :pad 8)
    (click (role button :name "Open folder nested"))
    (await-task)
    (settle)
    (screenshot "nested")))
