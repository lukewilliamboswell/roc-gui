(test "seek and status use the active production player"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (await-task)
    (click (role button :name "Seek forward"))
    (await-task)
    (expect-visible (text "Position 100 ms"))
    (click (role button :name "Refresh playback status"))
    (await-task)
    (expect-visible (text-prefix "Position "))))
