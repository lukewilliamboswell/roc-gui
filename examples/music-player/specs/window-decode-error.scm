; Photographs the failure state: the status surface carries the message, and the
; row the person clicked stays marked so the failure has somewhere to belong.
(test "A decode failure is legible against the night ground"
  (grants
    (directory "fixture")
    (audio null))
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
    (screenshot "chosen-row" :region (role button :name "Play broken.wav") :pad 8)
    (screenshot "status" :region (role panel :name "Playback status") :pad 12)))
