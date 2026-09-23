; Ten thousand result rows in the real window, of which only the rows near the
; viewport are ever built. Scrolling far past them leaves the list to build the
; rows it has reached; the first- and last-row keys move it from state; and the
; list reports the rows on screen back to the application, which names them.
(test "the browser scrolls ten thousand rows it builds only near the viewport"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    ; The editor holds "... LIMIT 100" with the caret at its end.
    (focus (role textarea :name "SQL query"))
    (type "00")
    (click (role button :name "Run query"))
    (await-task)
    (settle)
    (expect-visible (text "Rows: 10000"))
    (expect-rows (role virtual-list :name "Query rows") :count 10000 :first 0)
    (expect-on-screen (text "Result row 0"))
    (expect-visible (text-prefix "On screen 1–"))
    ; Four thousand rows down by distance: none of them was built before.
    (expect-count (text "Result row 4000") 0)
    (scroll (role virtual-list :name "Query rows") :by 96000)
    (settle)
    (expect-on-screen (text "Result row 4000"))
    (expect-rendered-count (text "Result row 4000") 1)
    (expect-count (text "Result row 0") 0)
    (expect-visible (text-prefix "On screen 4001–"))
    (screenshot "row-4000")
    ; The application asks for its last row.
    (click (role button :name "Scroll to last row"))
    (settle)
    (expect-on-screen (text "Result row 9999"))
    (expect-visible (text-prefix "On screen "))
    (expect-visible (text-prefix "Rows: 10000"))
    (screenshot "last-row")
    (screenshot "last-row-region" :region (role virtual-list :name "Query rows") :pad 4)
    ; And for its first.
    (click (role button :name "Scroll to first row"))
    (settle)
    (expect-on-screen (text "Result row 0"))
    (expect-visible (text-prefix "On screen 1–"))
    (expect-count (text "Result row 9999") 0)
    (screenshot "first-row")))
