; Photographs the ledger: hairline rules rather than boxes, a table whose
; columns sit on the same vertical rules as their headings, and the standing
; folder readout above both side rails.
(test "the browser presents a ruled ledger and a standing folder readout"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (expect-on-screen (role row :name "Browser header"))
    (expect-on-screen (role row :name "Authority bar"))
    (expect-on-screen (role column :name "Database files"))
    (expect-on-screen (role column :name "Database schema"))
    (expect-on-screen (role column :name "Query bench"))
    (expect-visible (text "choose a folder to read"))
    (screenshot "first-frame")
    (screenshot "authority-ungranted" :region (role row :name "Authority bar") :pad 4)
    (click (role button :name "Choose database folder"))
    (await-task)
    (settle)
    (expect-visible (text "read-only, this folder only"))
    (screenshot "folder-granted")
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (settle)
    (expect-on-screen (role textarea :name "SQL query"))
    (expect-visible (text "Table: books"))
    (screenshot "database-open")
    (click (role button :name "Run query"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Result columns"))
    (expect-visible (text "Rows: 100"))
    (screenshot "rows")
    (screenshot "table-head" :region (role row :name "Result columns") :pad 6)))
