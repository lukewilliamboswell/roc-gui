; Reversing a pause. A paused track resumes the same track rather than
; restarting the queue, the primary control says which way it will go, and the
; title above the status keeps naming the track the whole way through.
(test "a paused track resumes where it was left"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Paused"))
    ; Pausing changed the status line and not the title: the track is still
    ; named, so a person never has to go back to the queue to find their place.
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))

    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))

    ; Resuming kept the same track sounding: Next steps to its neighbour.
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Waltz in F major, Op. 34 No. 3"))
    (expect-visible (text "Playing"))
    (expect-audio-counters 1 1 1 2 3 1 0 0 1)))
