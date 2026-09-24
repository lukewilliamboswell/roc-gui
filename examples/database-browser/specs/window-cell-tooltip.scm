; A real pointer resting on a clipped cell: the note waits out its delay on
; the window's own clock, floats beside the cell over the rows below it, and
; Escape takes it away. The folder key's note opens to keyboard focus and
; closes when focus moves on.
(test "the browser explains a cell and its folder key in the real window"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (focus (role button :name "Choose database folder"))
    (await-count (role tooltip :name "About the folder grant") 1)
    (expect-on-screen (role tooltip :name "About the folder grant"))
    (screenshot "folder-note")
    (click (role button :name "Choose database folder"))
    (await-task)
    (focus (role button :name "Open database bookstore.db"))
    (await-count (role tooltip :name "About the folder grant") 0)
    (click (role button :name "Open database bookstore.db"))
    (await-task)
    (click (role button :name "Run query"))
    (await-task)
    (settle)
    (hover-enter (role row :name "title in result row 2"))
    (await-count (role tooltip :name "title in result row 2") 1)
    (expect-on-screen (role tooltip :name "title in result row 2"))
    (expect-bounds (role tooltip :name "title in result row 2") :min-width 60 :max-width 420 :min-height 20 :max-height 120)
    (screenshot "cell-note")
    (screenshot "cell-note-region" :region (role tooltip :name "title in result row 2") :pad 24)
    (press-key Escape)
    (await-count (role tooltip :name "title in result row 2") 0)
    (hover-exit (role row :name "title in result row 2"))
    (expect-popover-counters 2 1 1)))
