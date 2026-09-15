(test "an older load cannot replace a newer track"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (click (role button :name "Play track-002.wav"))
    (await-task)
    (await-task)
    (await-task)
    (expect-visible (text "Playing track-002.wav"))))
