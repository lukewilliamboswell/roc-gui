(test "Recreated nested grid cannot revive removed leaf tasks"
 (steps
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (hover-exit (role button :name "Cell 1"))
  (click (role button :name "Remove first quadrant"))
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  ; The removed leaf's reset was cancelled with its quadrant and never completes.
  (await-task-waits 0)
  (expect-task-counters 1 _ 0 0 1 _)
  (expect-background (role button :name "Cell 1") 0x66E0FF)))
