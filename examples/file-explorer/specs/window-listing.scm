; Photographs the listing in a real window. Every row opens with the drawn kind
; of its entry, so a directory reads as a shape before any of its names are
; read, and the folders stay distinguishable from the files at a glance. The
; selected row and the evidence of a read are photographed too: they are the
; only places the explorer spends its accent, and they have to look like the
; same decision.
(test "File explorer draws the kind of every entry"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (expect-on-screen (role column :name "No project"))
    (screenshot "empty")
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Folder entry nested"))
    (expect-on-screen (role row :name "File entry alpha.txt"))
    (expect-on-screen (role row :name "Directory toolbar"))
    (screenshot "listing")
    (screenshot "toolbar" :region (role row :name "Directory toolbar") :pad 8)
    (screenshot "folder-row" :region (role row :name "Folder entry nested") :pad 8)
    (click (role button :name "Select File: alpha.txt"))
    (settle)
    (expect-on-screen (role panel :name "Selection details"))
    (screenshot "selected")
    (click (role button :name "Read file alpha.txt"))
    (await-task)
    (settle)
    (expect-visible (text "Read 6 bytes"))
    (screenshot "read-result" :region (role panel :name "Selection details") :pad 12)
    (click (role button :name "Open folder nested"))
    (await-task)
    (settle)
    (expect-on-screen (role button :name "Back"))
    (screenshot "nested")))
