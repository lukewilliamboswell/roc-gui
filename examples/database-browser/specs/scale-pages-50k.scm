; The last page of a 50000-row result. One page stays resident however long
; the result is; what grows is how deep the page lies.
(test "turn to the last page of 50000 loans"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 50000 :change-size 10000)
  (steps (click (role button :name "Choose database folder")) (await-task) (click (role button :name "Open database bookstore.db")) (await-task) (replace-text (role textarea :name "SQL query") "SELECT * FROM loans WHERE id <= 50000 ORDER BY id") (click (role button :name "Run query")) (await-task) (click (role button :name "Next page")) (await-task) (click (role button :name "Next page")) (await-task) (click (role button :name "Next page")) (await-task) (mark-metrics) (click (role button :name "Next page")) (await-task) (expect-visible (text "Rows 40001–50000, end of result")) (expect-count (text-prefix "Result row ") 10000)))
