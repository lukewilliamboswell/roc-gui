;; The bar reports the folder the browser actually holds, and the header
;; reports the database actually open, from the moment each becomes true.
(test "the authority readout names the granted folder and the open database"
  (grants
    (directory "fixture"))
  (steps
    (expect-visible (text "choose a folder to read"))
    (click (role button :name "Choose database folder"))
    (await-task)
    (expect-visible (text "fixture"))
    (expect-visible (text "read-only, this folder only"))
    (expect-not-visible (role panel :name "Database error"))
    (expect-visible (text "Open a file to read its tables."))
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (expect-visible (text "TABLES IN bookstore.db"))
    (expect-visible (text "read-only handle on bookstore.db"))
    (expect-visible (text "Table: books"))
    (click (role button :name "Open database broken.db"))
    (await-task)
    (expect-visible (role panel :name "Database error"))
    (expect-visible (text "read-only, this folder only"))
    (expect-visible (text "fixture"))
    (expect-sqlite-counters 1 2 1)))
