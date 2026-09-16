(test "an older load cannot replace a newer track"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (click (role button :name "Play Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (await-task)
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))))
