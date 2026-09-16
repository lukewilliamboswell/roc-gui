; Photographs the failure state: the title still names the row the person
; pressed, the status line underneath carries the reason, and the row itself
; stays marked so the failure has somewhere to belong.
(test "A decode failure is legible against the night ground"
  (grants
    (directory "library")
    (audio null)
    (assets "assets"))
  (steps
    (settle)
    (click (role button :name "Choose music folder"))
    (await-task)
    (settle)
    (click (role button :name "Play Unknown - damaged recording"))
    (await-task)
    (settle)
    (expect-visible (text "Track could not be decoded"))
    (expect-visible (text "Unknown - damaged recording"))
    (screenshot "decode-error")
    (screenshot "chosen-row" :region (role button :name "Play Unknown - damaged recording") :pad 8)
    (screenshot "status" :region (role panel :name "Playback status") :pad 12)))
