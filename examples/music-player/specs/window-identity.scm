; Photographs the high-contrast night identity in a real window: the empty
; ground, a full queue, the sounding row carrying the accent, and the paused
; transport reading "Resume".
(test "Music player wears its night identity"
  (grants
    (directory "fixture")
    (audio null))
  (steps
    (settle)
    (expect-on-screen (role button :name "Choose music folder"))
    (screenshot "empty")
    (click (role button :name "Choose music folder"))
    (await-task)
    (settle)
    (expect-visible (text "201 tracks"))
    (screenshot "library")
    (screenshot "queue" :region (role virtual-list :name "Tracks") :pad 8)
    (click (role button :name "Play track-003.wav"))
    (await-task)
    (settle)
    (expect-visible (text "Playing track-003.wav"))
    (screenshot "playing")
    (screenshot "transport" :region (role row :name "Playback controls") :pad 12)
    (click (role button :name "Toggle playback"))
    (await-task)
    (settle)
    (expect-visible (text "Paused"))
    (screenshot "paused")))
