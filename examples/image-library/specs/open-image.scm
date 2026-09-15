(test "open capability-scoped image"
  (steps
    (click (role button :name "Choose image folder"))
    (await-task)
    (click (role button :name "Open image sunset.svg"))
    (await-task)
    (expect-visible (role image :name "Selected image"))
    (expect-image-bytes (role image :name "Selected image") 396)))
