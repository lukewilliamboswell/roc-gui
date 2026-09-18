(test "Recreated nested grid cannot revive removed leaf tasks"
 (steps
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (hover-exit (role button :name "Cell 1"))
  (click (role button :name "Remove first quadrant"))
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (await-task)
  (expect-background (role button :name "Cell 1") 0x66E0FF)
  (expect-component-work :rendered 0 :compared 0)))
