; A database opened from a project is derived from that project's grant, so
; revoking the project reaches the database. The resource access inventory
; recorded this as unverified, and it was: the snapshot is an independent
; in-memory copy, so nothing in SQLite's own code would have stopped a query
; after the directory it came from was taken away. Deriving the snapshot from
; the directory grant makes it true by construction rather than by a rule
; written twice, and this is the case that says so.
;
; Bytes already returned to application state are not recalled — the rows from
; the query before revocation are still on screen, and the contract says
; plainly that revocation cannot retract them. What must not happen is a new
; query succeeding.
(test "revoking a project reaches the databases opened from it"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive"
      "sqlite provisioned/consent-only derived read")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 100"))
    ; The project's authority is taken away. Both grants say so.
    (revoke-file-grants)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive revoked"
      "sqlite provisioned/consent-only derived read revoked")
    ; The rows already returned are still here, because revocation cannot
    ; recall what an application was already given.
    (expect-visible (text "Rows: 100"))
    ; A further query reaches the snapshot and is refused.
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (role panel :name "Database error"))))
