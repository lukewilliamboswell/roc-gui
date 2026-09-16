(test "record the animation studio gallery journey"
  (steps
    (settle)
    (screenshot "studio")
    (click (role button :name "Add rectangle"))
    (click (role button :name "Add keyframe"))
    (settle)
    (screenshot "editing")
    (click (role button :name "Play"))
    (screenshot "playing")))
