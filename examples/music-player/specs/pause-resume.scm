; Reversing a pause. A paused track resumes the same track rather than
; restarting the queue, and the primary control says which way it will go.
(test "a paused track resumes where it was left"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-002.wav"))
    (await-task)
    (expect-visible (text "Playing track-002.wav"))
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Paused"))
    
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Playing"))
    
    ; Resuming kept the same track sounding: Next steps to its neighbour.
    (click (role button :name "Next track"))
    (await-task)
    (await-task)
    (expect-visible (text "Playing track-003.wav"))
    (expect-audio-counters 1 1 1 2 3 1 0 0 1)))
