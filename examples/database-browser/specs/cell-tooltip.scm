; A result cell clips its value to the column, so resting the pointer on it
; opens a note with the whole value, its column, and its SQLite type. The note
; waits out its delay, closes when the pointer leaves, and Escape dismisses it.
(test "a result cell explains its value on hover"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose database folder"))
    (await-task)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (click (role button :name "Run query"))
    (await-task)
    (expect-count (text "Book 00001") 1)
    (hover-enter (role row :name "title in result row 0"))
    ; The delay has not elapsed, so nothing is presented yet.
    (expect-not-visible (role tooltip :name "title in result row 0"))
    (await-count (role tooltip :name "title in result row 0") 1)
    (expect-visible (within (role tooltip :name "title in result row 0") (text "title · TEXT")))
    (expect-visible (within (role tooltip :name "title in result row 0") (text "Book 00001")))
    (expect-count (text "Book 00001") 2)
    (hover-exit (role row :name "title in result row 0"))
    (expect-not-visible (role tooltip :name "title in result row 0"))
    (expect-count (text "Book 00001") 1)
    (expect-popover-counters 1 1 0)
    ; A number's note names its storage class too.
    (hover-enter (role row :name "price in result row 0"))
    (await-count (role tooltip :name "price in result row 0") 1)
    (expect-visible (within (role tooltip :name "price in result row 0") (text "price · REAL")))
    (press-key Escape)
    (expect-not-visible (role tooltip :name "price in result row 0"))
    (expect-popover-counters 2 1 1)))
