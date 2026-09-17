(test "Nested delegation stops at a depth-one quadrant"
 (steps
  (click (role button :name "Create 100 cells"))
  (click (role button :name "Cell 1"))
  (expect-component-work :rendered 37 :compared 0 :ancestor-invalidations 2)
  (expect-background (role column :name "Quadrant 1") 0x66E0FF)
  (expect-background (role column :name "Quadrant 2") 0x263247)
  (expect-background (role column :name "Quadrant 0") 0x263247)
  (expect-visible (text "Accepted: 0"))
  (click (role button :name "Inspect acceptance"))
  (expect-visible (text "Accepted: 1"))))
