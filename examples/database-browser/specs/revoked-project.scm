; A database opened from a project is derived from that project's grant, so
; revoking the project reaches the database. The connection is SQLite's own,
; so nothing in SQLite's code would stop a query after the directory it came
; from was taken away. Deriving the connection from the directory grant makes
; it true by construction rather than by a rule written twice, and this is the
; case that says so.
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
      "sqlite provisioned/consent-only derived read,derive")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 100"))
    ; The project's authority is taken away. Both grants say so.
    (revoke-file-grants)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive revoked"
      "sqlite provisioned/consent-only derived read,derive revoked")
    ; The rows already returned are still here, because revocation cannot
    ; recall what an application was already given.
    (expect-visible (text "Rows: 100"))
    ; A further query reaches the database and is refused — and says which
    ; refusal it was. Reporting a withdrawn grant as an invalid handle would
    ; tell a person their database is broken when someone simply took the
    ; folder back, and would be a different remedy on screen.
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text "SQLite authority was withdrawn"))))
