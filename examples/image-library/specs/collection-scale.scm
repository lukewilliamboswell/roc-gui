(test "browse a high-resolution collection through the ordinary gallery"
  (grants
    (directory "fixture"))
  (benchmark :warmups 1 :samples 3 :iterations 4 :scale 24 :initial-size 27 :change-size 24)
  (steps
    (click (role button :name "Open image folder"))
    (await-task)
    (expect-visible (text "27 of 27 entries"))
    (replace-text (role textbox :name "Filter images") "collection-")
    (expect-visible (text "24 of 27 entries"))
    (expect-count (button-prefix "View image collection-") 24)
    (click (role button :name "View image collection-01.svg"))
    (expect-image-bytes (role image :name "Selected image") 216)
    (mark-metrics)))
