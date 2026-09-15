; Photographs the failure state: the status surface carries the message while
; the queue keeps its ordinary row treatment.
(test "A decode failure is legible against the night ground"
  (steps
    (settle)
    (click (role button :name "Choose music folder"))
    (await-task)
    (settle)
    (click (role button :name "Play broken.wav"))
    (await-task)
    (settle)
    (expect-visible (text "Track could not be decoded"))
    (screenshot "decode-error")
    (screenshot "status" :region (role panel :name "Playback status") :pad 12)))
