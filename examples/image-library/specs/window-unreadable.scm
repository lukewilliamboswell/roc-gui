; An entry the decoder refused still occupies a picture's place on the wall, so
; the gallery stays a column of one shape rather than collapsing into a line of
; text wherever a file could not be read. This photographs that row: the glyph
; standing in for the picture, and the sentence beside it saying why there is
; none.
(test "an unreadable entry keeps a picture's place on the wall"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (click (role button :name "Open image folder"))
    (await-task)
    (settle)
    (expect-on-screen (text "27 of 27 entries"))
    (focus (role textbox :name "Filter images"))
    (type "corrupt")
    (settle)
    (expect-on-screen (text "1 of 27 entries"))
    (expect-on-screen (text "corrupt.svg — Corrupt image"))
    (expect-visible (role image :name "Unreadable image"))
    (screenshot "unreadable" :region (role column :name "Gallery") :pad 8)))
