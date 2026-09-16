(test "directory authority denial is explicit"
  (grants)
  (steps
    (expect-file-picks 0) (expect-file-lists 0) (expect-file-opens 0) (expect-file-reads 0)
    (expect-file-selection-counters 0 0 0 0 0 0 0)
    (click (role button :name "Open project"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-visible (text "Directory access was denied"))
    ; a refusal is a designed state, not a string: it says what the refusal
    ; means for what this window can reach, and carries the press that takes
    ; it back
    (expect-visible (text "Open a project to grant this window one folder. Nothing outside it can be reached."))
    (expect-visible (role button :name "Ask again"))
    (expect-file-picks 1) (expect-file-lists 0) (expect-file-opens 0) (expect-file-reads 0)))
