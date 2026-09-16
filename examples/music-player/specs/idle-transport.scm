; The very first press, before any folder has been granted. Every transport
; control is on screen from the start, so each one has to be harmless rather
; than merely unused: nothing sounds, nothing is acquired, and the invitation
; to choose a folder still stands.
(test "the transport is harmless before a folder is granted"
  (grants
    (directory "library")
    (audio null))
  (steps
    (expect-visible (text "Choose a music folder"))
    (expect-visible (text "Nothing playing"))
    (click (role button :name "Toggle playback"))
    (expect-visible (text "Choose a music folder"))
    (click (role button :name "Next track"))
    (expect-visible (text "Choose a music folder"))
    (click (role button :name "Previous track"))
    (expect-visible (text "Choose a music folder"))
    (click (role button :name "Stop playback"))
    (expect-visible (text "Choose a music folder"))
    (click (role button :name "Skip forward five seconds"))
    (expect-visible (text "Choose a music folder"))
    (click (role button :name "Show playback position"))
    (expect-visible (text "Choose a music folder"))
    ; Nothing was named as playing, no queue was invented, and no output or
    ; track was ever acquired.
    (expect-visible (text "Nothing playing"))
    (expect-not-visible (role virtual-list :name "Tracks"))
    (expect-visible (text "No folder chosen yet."))
    (expect-audio-counters 0 0 0 0 0 0 0 0 0)))
