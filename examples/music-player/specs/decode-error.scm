(test "a corrupt track is isolated"
  (steps
    (click (role button :name "Choose music folder"))
    (await-task)
    (click (role button :name "Play broken.wav"))
    (await-task)
    (expect-visible (text "Track could not be decoded"))
    (expect-count (role virtual-list :name "Tracks") 1)))
