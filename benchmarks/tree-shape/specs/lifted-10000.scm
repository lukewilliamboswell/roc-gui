(test "Lift and tear down 10000 nested containers with current-state delegation"
 (steps
  (click (role button :name "Build lifted tree of 10,000"))
  (expect-count (text-prefix "Lifted item ") 10000)
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 1"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 2"))
  (click (role button :name "Build deep tree of 10"))
  (expect-count (text-prefix "Outline item ") 10)))
