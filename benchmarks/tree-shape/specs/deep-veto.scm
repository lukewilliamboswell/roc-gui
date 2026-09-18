(test "A middle heterogeneous boundary veto discards the complete candidate"
 (steps
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (click (role button :name "Toggle middle veto"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 0"))
  (expect-component-work :rendered 0 :compared 0)
  (click (role button :name "Toggle middle veto"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 1"))))
