(test "Same-row quadrant reorder preserves leaf task ownership"
 (steps
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (hover-exit (role button :name "Cell 1"))
  (click (role button :name "Swap top quadrants"))
  (expect-component-work :mounted 0 :retired 0)
  (await-task)
  (expect-background (role button :name "Cell 1") 0x263247)
  (expect-component-work :rendered 1 :compared 0)))
