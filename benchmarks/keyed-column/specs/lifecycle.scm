(test "Keyed children retain local identity across structural edits"
  (steps
    (expect-visible (text "item 1 value 0"))
    (expect-visible (text "item 2 value 0"))
    (click (role button :name "Increment 2"))
    (expect-visible (text "item 2 value 1"))
    (click (role button :name "Move 2 first"))
    (expect-visible (text "item 2 value 1"))
    (click (role button :name "Task 2"))
    (await-task)
    (expect-visible (text "item 2 value 11"))
    (click (role button :name "Remove 2"))
    (expect-not-visible (text "item 2 value 11"))
    (expect-visible (text "item 1 value 0"))))
