(test "One thousand heterogeneous adapters delegate current state without recursive calls"
 (steps
  (click (role button :name "Build heterogeneous tree of 1,000"))
  (expect-component-work :mounted 1000)
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 1"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 2"))
  (click (role button :name "Build deep tree of 10"))
  (expect-component-work :retired 1000)))
