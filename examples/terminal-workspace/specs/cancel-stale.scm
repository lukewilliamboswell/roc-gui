(test "cancellation wakes a read and stale completion cannot revive a session"
  (grants
    (process test-program))
  (steps
    (click (role button :name "New terminal"))
    (await-task)
    (await-task)
    (click (role button :name "Stop terminal"))
    (await-task)
    (await-task)
    (expect-visible (text "Session canceled"))
    (expect-not-visible (text "Session active"))
    (expect-processes 0)))
