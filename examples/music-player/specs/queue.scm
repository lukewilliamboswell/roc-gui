(test "next advances the playback queue"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (await-task)
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))))
