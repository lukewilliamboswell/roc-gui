(test "Deep heterogeneous owner removal discards completion after key reuse"
 (steps
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Queue deepest edit"))
  (click (role button :name "Build deep tree of 10"))
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Increment deepest leaf"))
  (await-task)
  (expect-visible (text "Deep value 1"))
  (expect-component-work :rendered 0 :compared 0)))
