(test "Replacing the grid discards late resets belonging to the removed cells"
  (steps
    (click (role button :name "Create 100 cells"))
    (hover-enter (role button :name "Cell 1"))
    (hover-exit (role button :name "Cell 1"))
    (click (role button :name "Reset grid"))
    (expect-component-work :mounted 100 :retired 100)
    (hover-enter (role button :name "Cell 1"))
    ; The removed cell's reset was cancelled with it: it never completes, and
    ; once its worker has unwound, nothing it started is left running.
    (await-task-waits 0)
    (expect-task-counters 1 _ 0 0 1 _)
    (expect-background (role button :name "Cell 1") 0x66E0FF)
    (expect-subscriptions 0)))
