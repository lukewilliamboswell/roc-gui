; The refusal, alone, because it is the state a person is least prepared for.
(test "a refused grant is a surface, not a sentence in a field"
  (steps
    (settle)
    (click (role button :name "Discover devices"))
    (await-task)
    (settle)
    (expect-on-screen (text "Device access denied"))
    (expect-on-screen (text "Blocked"))
    (expect-on-screen (text "Nothing was searched for."))
    (expect-not-visible (role button :name "Connect device"))
    ; The remedy is on screen where the control that cannot reach it was.
    (expect-on-screen (text "A device is granted when the application starts. Start it again with a device grant to search."))
    (expect-bounds (role row :name "Status") :min-height 58 :max-height 78)
    (screenshot "refused")))
