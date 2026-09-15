(test "stopping cancels playback state"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (await-task)
    (click (role button :name "Stop playback"))
    (await-task)
    (expect-visible (text "Stopped"))))
