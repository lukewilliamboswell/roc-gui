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
    (expect-not-visible (role virtual-list :name "Directory entries"))
    ; the refusal's own control asks again too, so a person does not have to
    ; leave the explanation to act on it
    (click (role button :name "Ask again"))
    (await-task)
    (expect-file-picks 3)
    (expect-visible (text "Directory access was denied"))
    (expect-visible (role button :name "Ask again"))
    (expect-not-visible (role virtual-list :name "Directory entries"))))
