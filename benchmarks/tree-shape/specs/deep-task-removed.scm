(test "Deep heterogeneous owner removal discards completion after key reuse"
 (steps
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Queue deepest edit"))
  (click (role button :name "Build deep tree of 10"))
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Increment deepest leaf"))
  ; The removed owner's queued edit was cancelled with it and never arrives.
  (await-task-waits 0)
  (expect-task-counters 1 _ 0 0 1 _)
  (expect-visible (text "Deep value 1"))))
