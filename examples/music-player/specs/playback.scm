(test "scan and play through the production decoder and mixer"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (expect-visible (text "201 tracks"))
    (click (role button :name "Play track-001.wav"))
    (await-task)
    (expect-visible (text "Playing track-001.wav"))
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Paused"))
    (expect-audio-counters 1 1 1 1 1 1 0 0 0)))
