(test "Removing a quadrant discards its leaf completion after recreation"
 (steps
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (hover-exit (role button :name "Cell 1"))
  (hover-enter (role button :name "Cell 100"))
  (hover-exit (role button :name "Cell 100"))
  (click (role button :name "Remove first quadrant"))
  (expect-count (button-prefix "Cell ") 75)
  ; Cell 1's reset was cancelled with its quadrant; only Cell 100's arrives.
  (await-task)
  (await-task-waits 0)
  (expect-task-counters 2 _ 1 0 1 _)
  (expect-background (role button :name "Cell 100") 0x263247)
  (click (role button :name "Create 100 cells"))
  (hover-enter (role button :name "Cell 1"))
  (expect-background (role button :name "Cell 1") 0x66E0FF)
))
