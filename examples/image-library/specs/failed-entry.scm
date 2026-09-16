; Acting on an entry that failed. A corrupt or unsupported file is listed with
; its reason and offers no way into the viewer, so a person cannot open one and
; land on a blank picture; and a filter that matches nothing says so.
(test "a failed entry names its reason and offers no viewer"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Open image folder"))
    (await-task)
    (replace-text (role textbox :name "Filter images") "corrupt.svg")
    (expect-visible (text "1 of 27 entries"))
    (expect-visible (text "corrupt.svg — Corrupt image"))
    (expect-not-visible (role button :name "View image corrupt.svg"))
    (expect-not-visible (role image :name "Thumbnail corrupt.svg"))
    (expect-not-visible (role image :name "Selected image"))
    (replace-text (role textbox :name "Filter images") "notes.txt")
    (expect-visible (text "notes.txt — Unsupported format"))
    (expect-not-visible (role button :name "View image notes.txt"))
    ; A filter nothing matches leaves an honest empty gallery.
    (replace-text (role textbox :name "Filter images") "no-such-image")
    (expect-visible (text "0 of 27 entries"))
    (expect-not-visible (button-prefix "View image "))
    ; Clearing the filter brings the folder back.
    (replace-text (role textbox :name "Filter images") "")
    (expect-visible (text "27 of 27 entries"))))
