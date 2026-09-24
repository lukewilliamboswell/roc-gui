; The last page of a 20000-row result. One page stays resident however long
; the result is; what grows is how deep the page lies.
(test "turn to the last page of 20000 loans"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 20000 :change-size 10000)
  (steps (click (role button :name "Choose database folder")) (await-task) (click (role button :name "Open database bookstore.db")) (await-task) (replace-text (role textarea :name "SQL query") "SELECT * FROM loans WHERE id <= 20000 ORDER BY id") (click (role button :name "Run query")) (await-task) (mark-metrics) (click (role button :name "Next page")) (await-task) (expect-visible (text "Rows 10001–20000, end of result")) (expect-rows (role virtual-list :name "Query rows") :count 10000 :first 0 :mounted 64)))
