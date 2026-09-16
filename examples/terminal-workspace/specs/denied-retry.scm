(test "a denied terminal can be asked for again and starts no session"
  (grants)
  (steps
    (expect-visible (text "gen 0"))
    (click (role button :name "New terminal"))
    (await-task)
    (expect-visible (text "Process access denied"))
    (expect-visible (text "gen 1"))
    (expect-processes 0)
    (click (role button :name "New terminal"))
    (await-task)
    (expect-visible (text "Process access denied"))
    (expect-visible (text "gen 2"))
    (expect-processes 0)
    (expect-count (text-prefix "line-") 0)
    (expect-visible (text "0/0 lines"))
    ; A refusal is a designed state, not a void: the well says which grant was
    ; missing and the exact flag that supplies it, and it survives a retry.
    (expect-visible (text-prefix "This workspace spawns a shell only through a grant"))))
