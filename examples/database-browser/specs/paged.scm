; A result longer than the host's row limit is read a page at a time. The first
; page runs the statement as written; later pages bind their offset as a
; parameter, and the host reports whether rows follow the page it returned.
(test "a result longer than one page turns page by page"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (expect-visible (text "Table: loans"))
    (replace-text (role textarea :name "SQL query") "SELECT id, book, day FROM loans ORDER BY id LIMIT 15000;")
    (click (role button :name "Run query"))
    (await-task)
    (expect-visible (text "Rows: 10000"))
    (expect-visible (text "Rows 1–10000, more follow"))
    (expect-count (role button :name "Previous page") 0)
    (click (role button :name "Next page"))
    (await-task)
    (expect-visible (text "Rows: 5000"))
    (expect-visible (text "Rows 10001–15000, end of result"))
    (expect-count (text-prefix "Result row ") 5000)
    (expect-visible (text "Result row 10000"))
    (expect-count (role button :name "Next page") 0)
    (click (role button :name "Previous page"))
    (await-task)
    (expect-visible (text "Rows 1–10000, more follow"))
    (expect-visible (text "Result row 0"))
    (expect-sqlite-counters 1 1 4)))
