(test "scan and play through the production decoder and mixer"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    ; The five rows are the four recordings and the damaged file; the notice
    ; beside them is not audio and is not offered as a track.
    (expect-visible (text "5 tracks"))
    (expect-not-visible (role button :name "Play NOTICE"))
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (await-task)
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (expect-visible (text "Playing"))
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Paused"))
    (expect-audio-counters 1 1 1 1 1 1 0 0 0)))
