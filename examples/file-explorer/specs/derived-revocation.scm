(test "revocation follows a derived child after its parent is retained"
  (steps
    (click (role button :name "Open project"))
    (await-task)
    (click (role button :name "Open folder nested"))
    (await-task)
    (expect-file-lifecycle-counters 1 1 2 0 0 0)
    (revoke-file-grants)
    (click (role button :name "Refresh directory"))
    (await-task)
    (expect-visible (text "The directory grant was revoked"))
    (expect-file-lifecycle-counters 1 1 2 1 1 1)))
