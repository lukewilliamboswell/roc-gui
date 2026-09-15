; Claims the semantic runner cannot make: these assert the controls were laid
; out in a real window and are actually on screen, not merely mounted. The
; card and control sizes are part of the example's visual identity, so they are
; pinned here rather than left to host defaults.
(test "Counter controls are laid out on screen in a real window"
  (steps
    (settle)
    (expect-visible (text "Counter"))
    (expect-on-screen (text "Counter"))
    (expect-on-screen (text "Two independent tallies, each its own state boundary"))
    (expect-on-screen (role column :name "Left counter"))
    (expect-on-screen (role column :name "Right counter"))
    (expect-on-screen (role button :name "Left increment"))
    (expect-on-screen (role button :name "Right decrement"))
    (expect-bounds (role column :name "Left counter") :min-width 224 :max-width 236 :min-height 236 :max-height 248)
    (expect-bounds (role button :name "Left increment") :min-width 50 :max-width 60 :min-height 34 :max-height 44)))
