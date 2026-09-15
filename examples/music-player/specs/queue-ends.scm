; The ends of the queue. Previous on the first row stays put rather than
; wrapping onto the last, and Next on the last row stays there rather than
; falling off the end.
(test "the queue clamps at its first and last rows"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-001.wav"))
    (await-task)
    ; track-001.wav is the second row; one Previous reaches the first, which is
    ; the corrupt file.
    (click (role button :name "Previous track"))
    (await-task)
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; Pressing Previous again on the first row leaves it there.
    (click (role button :name "Previous track"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; Stepping forward from the row that failed reaches its neighbour, not the
    ; row that was sounding before the step.
    (click (role button :name "Next track"))
    (await-task)
    (expect-visible (text "Playing track-001.wav"))
    ; The last row is the other boundary.
    (click (role button :name "Play track-200.wav"))
    (await-task)
    (expect-visible (text "Playing track-200.wav"))
    ; Next holds the last row rather than running off the end or going silent.
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Playing track-200.wav"))))
