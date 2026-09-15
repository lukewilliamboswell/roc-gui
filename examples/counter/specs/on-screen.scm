; Claims the semantic runner cannot make: these assert the controls were laid
; out in a real window and are actually on screen, not merely mounted.
(test "Counter controls are laid out on screen in a real window"
  (steps
    (settle)
    (expect-visible (text "Counter"))
    (expect-on-screen (text "Counter"))
    (expect-on-screen (role button :name "Left increment"))
    (expect-on-screen (role button :name "Right decrement"))
    (expect-bounds (role button :name "Left increment") :min-width 20 :min-height 12)))
