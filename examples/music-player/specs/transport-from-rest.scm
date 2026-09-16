; A transport is not inert because nothing is sounding. This walks the path a
; person actually takes: press Play, land on the corrupt first track, and then
; use Next and the queue itself to get somewhere.
(test "next and the queue work from a stopped transport"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; Next steps away from the row that failed, not from nothing.
    (click (role button :name "Next track"))
    (await-task)
    (expect-visible (text "Playing track-001.wav"))
    ; And a queue row can still be chosen directly while another is sounding.
    (click (role button :name "Play track-003.wav"))
    (await-task)
    (expect-visible (text "Playing track-003.wav"))
    ; Previous steps back from the sounding row.
    (click (role button :name "Previous track"))
    (await-task)
    (await-task)
    (expect-visible (text "Playing track-002.wav"))))
