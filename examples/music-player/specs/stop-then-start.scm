; Acting from rest after a deliberate stop. Stopping forgets the chosen row, so
; Previous starts from the end of the queue and Play starts from the top, and a
; second Stop on an already stopped transport changes nothing.
(test "the transport restarts from rest after a stop"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Chopin - Polonaise in E-flat minor, Op. 26 No. 2"))
    (await-task)
    (click (role button :name "Stop playback"))
    (await-task)
    (expect-visible (text "Stopped"))
    (expect-visible (text "Nothing playing"))
    ; Pressing Stop again from rest is not an error and not a new task.
    (click (role button :name "Stop playback"))
    (expect-visible (text "Stopped"))
    ; With no chosen row, Previous begins at the last row in the queue, which is
    ; the damaged recording: the row is named and the failure is reported.
    (click (role button :name "Previous track"))
    (await-task)
    (expect-visible (text "Unknown - damaged recording"))
    (expect-visible (text "Track could not be decoded"))
    ; And Play from rest begins at the top of the queue, which is music. The
    ; first press a person ever makes on an untouched library must reach a
    ; recording, never the one file that cannot be decoded.
    (click (role button :name "Stop playback"))
    (click (role button :name "Toggle playback"))
    (await-task)
    (expect-visible (text "Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (expect-visible (text "Playing"))))
