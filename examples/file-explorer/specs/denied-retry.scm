(test "a refused project grant can be asked for again"
  (grants)
  (steps
    (click (role button :name "Open project"))
    (await-task)
    (expect-visible (role panel :name "Directory error"))
    (expect-visible (text "Directory access was denied"))
    (expect-visible (text "Open a project to begin"))
    (expect-file-picks 1)
    (click (role button :name "Open project"))
    (await-task)
    (expect-visible (text "Directory access was denied"))
    (expect-file-picks 2)
    (expect-not-visible (role virtual-list :name "Directory entries"))))
