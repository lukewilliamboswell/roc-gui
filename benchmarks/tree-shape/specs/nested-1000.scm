(test "Build and retire one thousand translation owners"
 (steps
  (click (role button :name "Build nested tree of 1,000"))
  (expect-component-work :mounted 1000)
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 1"))
  (click (role button :name "Increment deepest leaf"))
  (expect-visible (text "Deep value 2"))
  (click (role button :name "Build deep tree of 10"))
  (expect-component-work :retired 1000)
  (expect-count (text-prefix "Outline item ") 10)))
