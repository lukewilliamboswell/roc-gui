(test "record the image library gallery journey"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (screenshot "empty")
    (click (role button :name "Open image folder"))
    (await-count (text "27 of 27 entries") 1)
    (settle)
    (screenshot "collection")
    (click (role button :name "View image collection-01.svg"))
    (settle)
    (screenshot "viewer")))
