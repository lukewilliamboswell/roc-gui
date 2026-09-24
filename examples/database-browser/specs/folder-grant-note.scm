; The folder key carries a note about the authority it asks for. Keyboard focus
; opens it at once, with no hover delay; focus leaving closes it, and Escape
; dismisses it while focus stays.
(test "the folder key explains its grant to keyboard focus"
  (grants
    (directory "fixture"))
  (steps
    (expect-not-visible (role tooltip :name "About the folder grant"))
    (focus (role button :name "Choose database folder"))
    (expect-visible (role tooltip :name "About the folder grant"))
    (expect-visible (within (role tooltip :name "About the folder grant") (text-prefix "The browser reads only the one folder")))
    (click (role button :name "Choose database folder"))
    (await-task)
    (focus (role button :name "Open database bookstore.db"))
    (expect-not-visible (role tooltip :name "About the folder grant"))
    (expect-popover-counters 1 1 0)
    (focus (role button :name "Choose database folder"))
    (expect-visible (role tooltip :name "About the folder grant"))
    (press-key Escape)
    (expect-not-visible (role tooltip :name "About the folder grant"))
    (expect-popover-counters 2 1 1)))
