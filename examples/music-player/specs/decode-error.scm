; A media application that has never been seen failing a file is not evidence of
; anything. The damaged recording is a real file in the shipped library, and it
; fails alone: the queue it sits in is untouched and every other row stays
; playable.
(test "a damaged recording is isolated"
  (grants
    (directory "library")
    (audio null))
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play Unknown - damaged recording"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    ; The row the person pressed is named above the failure, so the message has
    ; something to be about.
    (expect-visible (text "Unknown - damaged recording"))
    (expect-count (role virtual-list :name "Tracks") 1)))
