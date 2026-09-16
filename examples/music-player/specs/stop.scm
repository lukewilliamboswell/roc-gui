(test "stopping cancels playback state"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (await-task)
    (click (role button :name "Stop playback"))
    (await-task)
    (expect-visible (text "Stopped"))))
