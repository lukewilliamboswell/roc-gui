; The chooser opened and was closed again. No authority was produced and
; nothing failed, and the explorer has to say the second thing: no error panel,
; no accusation, and — when a project is already open — no disturbance at all.
(test "a dismissed chooser is rest, not refusal"
  (grants
    (directory canceled))
  (steps
    (expect-visible (text "Open a project to begin"))
    (click (role button :name "Open project"))
    (await-task)
    (expect-file-picks 1)
    (expect-visible (text "No project chosen"))
    (expect-not-visible (role panel :name "Directory error"))
    (expect-not-visible (role button :name "Ask again"))
    (expect-not-visible (text "Open a project to begin"))
    ; nothing was granted, so nothing was listed and nothing can be closed
    (expect-file-lists 0)
    (expect-not-visible (role virtual-list :name "Directory entries"))
    (expect-not-visible (role button :name "Close directory"))
    ; and the action that asks for authority is available again straight away
    (expect-visible (role button :name "Open project"))))
