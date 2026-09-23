; Every mounted cell of a ten-thousand-row answer is a hover anchor. Opening
; and closing one cell's note is a presentation change owned by the graph: it
; renders nothing in the application and leaves every other note closed.
(test "hover one cell among ten thousand rows"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (replace-text (role textarea :name "SQL query") "SELECT * FROM books LIMIT 10000")
    (click (role button :name "Run query"))
    (await-task)
    (expect-rows (role virtual-list :name "Query rows") :count 10000 :first 0 :mounted 64)
    (click (role button :name "Scroll to last row"))
    (expect-visible (text "Result row 9999"))
    (mark-metrics)
    (hover-enter (role row :name "title in result row 9999"))
    (await-count (role tooltip :name "title in result row 9999") 1)
    (expect-visible (within (role tooltip :name "title in result row 9999") (text "title · TEXT")))
    (hover-exit (role row :name "title in result row 9999"))
    (expect-count (role tooltip :name "title in result row 9999") 0)
    (expect-popover-counters 1 1 0)))
