(test "a terminal without a host grant is denied"
  (steps
    (click (role button :name "New terminal"))
    (await-task)
    (expect-visible (text "Process access denied"))
    (expect-processes 0)))
