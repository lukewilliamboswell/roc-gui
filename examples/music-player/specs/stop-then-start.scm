; Acting from rest after a deliberate stop. Stopping forgets the chosen row, so
; Previous starts from the end of the queue and Play starts from the top, and a
; second Stop on an already stopped transport changes nothing.
(test "the transport restarts from rest after a stop"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play track-002.wav"))
    (await-task)
    (click (role button :name "Stop playback"))
    (await-task)
    (expect-visible (text "Stopped"))
    ; Pressing Stop again from rest is not an error and not a new task.
    (click (role button :name "Stop playback"))
    (expect-visible (text "Stopped"))
    ; With no chosen row, Previous begins at the last track in the queue.
    (click (role button :name "Previous track"))
    (await-task)
    (expect-visible (text "Playing track-200.wav"))
    (click (role button :name "Stop playback"))
    (await-task)
    ; And Play from rest begins at the top of the queue, which is the corrupt
    ; file: the failure is reported instead of the transport going quiet.
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))))
