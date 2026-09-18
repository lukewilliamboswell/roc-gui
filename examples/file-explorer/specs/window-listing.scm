; Photographs the listing in a real window. Every row opens with the drawn kind
; of its entry, so a directory reads as a shape before any of its names are
; read, and the folders stay distinguishable from the files at a glance. The
; selected row and the evidence of a read are photographed too: they are the
; only places the explorer spends its accent, and they have to look like the
; same decision.
;
; The counters and the grants are asserted here rather than only in a semantic
; case because this is the run in which the authority was actually exercised
; through the window: the photograph, the authority behind it, and the count of
; what it did are one piece of evidence rather than three that have to be
; believed together.
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
    (expect-file-picks 1)
    (expect-file-lists 1)
    (expect-file-reads 0)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive")
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
    (expect-file-reads 1)
    (screenshot "read-result" :region (role panel :name "Selection details") :pad 12)
    (click (role button :name "Open folder nested"))
    (await-task)
    (settle)
    (expect-file-lists 2)
    ; The folder opened from the project is a grant derived beneath it, and the
    ; window says so from the same registry the semantic runner reads.
    (expect-grants
      "directory provisioned/consent-only root read,list,derive"
      "directory provisioned/consent-only derived read,list,derive")
    (expect-on-screen (role button :name "Back"))
    (screenshot "nested")))
