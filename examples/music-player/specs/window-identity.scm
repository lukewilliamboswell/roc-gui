; Photographs the high-contrast night identity in a real window: the empty
; ground, the shipped library of real recordings, the sounding row carrying the
; accent, and the paused transport reading "Resume" over a title that has not
; moved.
(test "Music player wears its night identity"
  (grants
    (directory "library")
    (audio null)
    (assets "assets"))
  (steps
    (settle)
    (expect-on-screen (role button :name "Choose music folder"))
    (screenshot "empty")
    (click (role button :name "Choose music folder"))
    (await-task)
    (settle)
    (expect-visible (text "5 tracks"))
    (screenshot "library")
    (screenshot "queue" :region (role virtual-list :name "Tracks") :pad 8)
    (click (role button :name "Play Chopin - Waltz in F major, Op. 34 No. 3"))
    (await-task)
    (settle)
    (expect-visible (text "Chopin - Waltz in F major, Op. 34 No. 3"))
    (expect-visible (text "Playing"))
    (screenshot "playing")
    (screenshot "now-playing" :region (role panel :name "Playback status") :pad 12)
    (screenshot "transport" :region (role row :name "Playback controls") :pad 12)
    (click (role button :name "Toggle playback"))
    (await-task)
    (settle)
    (expect-visible (text "Paused"))
    (screenshot "paused")))
