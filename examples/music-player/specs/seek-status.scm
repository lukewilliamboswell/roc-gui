; Skipping is a relative move, not a jump to a fixed millisecond: the position
; is read first and the seek goes to where the track actually is plus five
; seconds. Pressing it twice is what tells the two apart, so it is pressed
; twice.
(test "skip and position use the active production player"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (await-task)
    (click (role button :name "Skip forward five seconds"))
    (await-task)
    (expect-visible (text "Position 5000 ms"))
    (click (role button :name "Show playback position"))
    (await-task)
    (expect-visible (text-prefix "Position "))
    ; The track is still named while the position is being read.
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))))
