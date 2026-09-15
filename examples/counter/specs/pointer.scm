; Pointer activation. The click itself is simulated at the production handler,
; but whether it could have landed is answered from real laid-out geometry:
; painted this frame, unclipped, enabled, and not behind a modal dialog.
(test "Counter responds to pointer activation"
  (steps
    (settle)
    (expect-visible (text "3"))
    (click (role button :name "Right increment"))
    (expect-visible (text "4"))
    (click (role button :name "Right decrement"))
    (click (role button :name "Right decrement"))
    (expect-visible (text "2"))
    (screenshot "after-clicks")))
