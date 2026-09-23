;; One chosen capture opens without a folder (US-1). The file grant reads that
;; file and nothing beside it, and the database opened from it is derived from
;; the file grant, so withdrawing the file withdraws the connection with it.
(test "a single chosen capture opens read-only and is withdrawn with its file"
  (grants
    (file "fixture/captures/database-browser-scale-100.rgstats"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-selected (role tab :name "database-browser-scale-100.rgstats"))
    (expect-visible (within (role row :name "Capture bar") (text "schema 25")))
    (expect-visible (within (role panel :name "Tile Outcome") (text "4/4 runs pass")))
    (expect-not-visible (role virtual-list :name "Captures"))
    (expect-visible (text "no folder granted"))
    ; Observatory keeps the file as well as the database opened from it, so
    ; a replaced capture can be read again from the same grant.
    (expect-grants
      "document provisioned/consent-only root read,derive"
      "sqlite provisioned/consent-only derived read,derive")
    (expect-document-counters 1 1 0 0 0 1)
    (revoke-file-grants)
    ; Withdrawing file grants reaches the connection through its lineage.
    (expect-grants
      "document provisioned/consent-only root read,derive revoked"
      "sqlite provisioned/consent-only derived read,derive revoked")
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (role panel :name "Capture error"))
    (expect-visible (text-prefix "This cycle's detail could not be read"))))
