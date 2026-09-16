(test "next advances the playback queue"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (await-task)
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Playing track-002.wav"))))
