;; One chosen capture opens without a folder (US-1). The file grant reads that
;; file and nothing beside it, and the database opened from it is derived from
;; the file grant, so withdrawing the file withdraws the connection even after
;; the file handle itself has been released.
(test "a single chosen capture opens read-only and is withdrawn with its file"
  (grants
    (file "fixture/captures/database-browser-scale-100.rgstats"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-visible (within (role row :name "Capture bar") (text "database-browser-scale-100.rgstats")))
    (expect-visible (within (role row :name "Capture bar") (text "schema 22")))
    (expect-visible (within (role panel :name "Tile Outcome") (text "4/4 runs pass")))
    (expect-not-visible (role virtual-list :name "Captures"))
    (expect-visible (text "no folder granted"))
    ; Observatory keeps the database, not the file, so the file handle is
    ; released and only the connection derived from it is held.
    (expect-grants
      "sqlite provisioned/consent-only derived read,derive")
    (expect-document-counters 1 1 0 0 0 0)
    (revoke-file-grants)
    ; Withdrawing file grants reaches the connection through its lineage,
    ; although the file handle itself is already gone.
    (expect-grants
      "sqlite provisioned/consent-only derived read,derive revoked")
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text-prefix "This cycle's detail could not be read"))))
