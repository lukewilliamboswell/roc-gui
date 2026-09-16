; A transport is not inert because nothing is sounding. This walks the path a
; person actually takes on a library they have just granted: press Play, and
; then use Next and the queue itself to get somewhere.
(test "next and the queue work from a stopped transport"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    ; The very first press on an untouched library reaches music.
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (expect-visible (text "Playing"))
    ; Next steps from the sounding row.
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))
    ; A queue row can still be chosen directly while another is sounding.
    (click (role button :name "Play Chopin - Waltz in F major, Op. 34 No. 3"))
    (await-task)
    (expect-visible (text "Chopin - Waltz in F major, Op. 34 No. 3"))
    (expect-visible (text "Playing"))
    ; Choosing a row that cannot be decoded does not stop the music that is
    ; already sounding: only the load failed, so the waltz plays on and the
    ; failure is reported against the row that was pressed.
    (click (role button :name "Play Unknown - damaged recording"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    (expect-visible (text "Unknown - damaged recording"))
    ; Previous therefore steps back from the row that is really sounding, not
    ; from the row that refused to load.
    (click (role button :name "Previous track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (expect-visible (text "Playing"))))
