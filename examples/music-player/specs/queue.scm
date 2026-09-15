(test "next advances the playback queue"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (await-task)
    (click (role button :name "Next track"))
    (await-task)
    (expect-visible (text "Playing track-002.wav"))))
