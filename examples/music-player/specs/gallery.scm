(test "record the music player gallery journey"
  (grants
    (directory "fixture")
    (audio null)
    (assets "assets"))
  (steps
    (settle)
    (screenshot "empty")
    (click (role button :name "Choose music folder"))
    (await-task)
    (settle)
    (screenshot "library")
    (click (role button :name "Play track-003.wav"))
    (await-task)
    (settle)
    (screenshot "playing")))
