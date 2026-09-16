(test "the gallery wall presents an empty wall, a populated wall, and one work"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (expect-on-screen (role row :name "Library header"))
    (expect-on-screen (role column :name "Gallery"))
    (expect-on-screen (text "No folder open"))
    (screenshot "empty")
    (click (role button :name "Open image folder"))
    ; The scan lands when it lands: wait for the tally it produces rather than
    ; for a settle that cannot know the task finished.
    (await-count (text "27 of 27 entries") 1)
    (expect-on-screen (text "27 of 27 entries"))
    (screenshot "populated")
    (focus (role textbox :name "Filter images"))
    (type "collection-")
    (settle)
    (expect-on-screen (text "24 of 27 entries"))
    (screenshot "filtered")
    (click (role button :name "View image collection-01.svg"))
    (settle)
    (expect-on-screen (role row :name "Image title"))
    ; The declared box is the box: a thumbnail is the square it says it is
    ; beside a caption long enough to have squeezed it, and the viewer image
    ; fits the space left for it rather than laying out past the window.
    (expect-bounds (role image :name "Thumbnail collection-01.svg")
      :min-width 88 :max-width 88 :min-height 88 :max-height 88)
    (expect-on-screen (role image :name "Selected image"))
    (screenshot "work")
    (screenshot "gallery" :region (role column :name "Gallery") :pad 8)))
