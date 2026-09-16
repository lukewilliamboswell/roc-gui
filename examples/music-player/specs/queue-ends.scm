; The ends of the queue. Previous on the first row stays put rather than
; wrapping onto the last, and Next on the last row stays there rather than
; falling off the end — including when the last row is the one that cannot be
; decoded, where a clamp that failed would look exactly like a crash.
(test "the queue clamps at its first and last rows"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (await-task)
    ; One Previous reaches the first row.
    (click (role button :name "Previous track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (expect-visible (text "Playing"))
    ; Pressing Previous again on the first row leaves it there.
    (click (role button :name "Previous track"))
    (await-task)
    (await-task)
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (expect-visible (text "Playing"))
    ; The last row is the other boundary, and it is the damaged recording.
    (click (role button :name "Play Schubert - Impromptu in C major, D. 946 No. 3"))
    (await-task)
    (expect-visible (text "Schubert - Impromptu in C major, D. 946 No. 3"))
    (expect-visible (text "Playing"))
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; Next holds the last row rather than running off the end, and says so
    ; again rather than going quiet.
    (click (role button :name "Next track"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; Stepping back from the row that failed reaches its neighbour, not the row
    ; that was sounding before the step.
    (click (role button :name "Previous track"))
    (await-task)
    (expect-visible (text "Schubert - Impromptu in C major, D. 946 No. 3"))
    (expect-visible (text "Playing"))))
