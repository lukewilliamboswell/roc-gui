(test "directory authority denial is explicit"
  (grants)
  (steps
    (expect-file-picks 0) (expect-file-lists 0) (expect-file-opens 0) (expect-file-reads 0)
    (expect-file-selection-counters 0 0 0 0 0 0 0)
    (click (role button :name "Open project"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-visible (text "Directory access was denied"))
    (expect-file-picks 1) (expect-file-lists 0) (expect-file-opens 0) (expect-file-reads 0)))
