; Photographs a long statement running with its Cancel key, then the note the
; browser leaves once the statement was stopped where it ran.
(test "a running query offers Cancel and says it was cancelled"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (settle)
    (focus (role textarea :name "SQL query"))
    ; The editor holds the opening statement; typing at its end makes it one
    ; whose offset takes minutes to count.
    (type " OFFSET (")
    (key "enter")
    (type "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL")
    (key "enter")
    (type "SELECT i + 1 FROM n WHERE i < 1000000000)")
    (key "enter")
    (type "SELECT count(*) FROM n)")
    (click (role button :name "Run query"))
    (expect-on-screen (role button :name "Cancel query"))
    (expect-visible (text "running…"))
    (screenshot "query-running" :region (role row :name "Query controls") :pad 6)
    (click (role button :name "Cancel query"))
    (await-task)
    (settle)
    (expect-visible (text "query cancelled"))
    (expect-not-visible (role button :name "Cancel query"))
    (screenshot "query-cancelled" :region (role row :name "Query controls") :pad 6)))
