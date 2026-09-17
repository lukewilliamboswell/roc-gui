(test "Replacing the grid discards late resets belonging to the removed cells"
  (steps
    (click (role button :name "Create 100 cells"))
    (hover-enter (role button :name "Cell 1"))
    (hover-exit (role button :name "Cell 1"))
    (click (role button :name "Reset grid"))
    (expect-component-work :mounted 100 :retired 100)
    (hover-enter (role button :name "Cell 1"))
    (await-task)
    (expect-background (role button :name "Cell 1") 0x66E0FF)
    (expect-component-work :rendered 0 :compared 0)
    (expect-subscriptions 0)))
