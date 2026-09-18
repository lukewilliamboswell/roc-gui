(test "Deep heterogeneous completion projects current state after intervening edit"
 (steps
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Queue deepest edit"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 1"))
  (await-task)
  (expect-visible (text "Deep value 2"))))
