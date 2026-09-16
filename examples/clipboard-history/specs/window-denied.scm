; A refusal on this subject has to be photographed, because the thing being
; claimed is visual: that a person who is refused sees a full account of what
; did not happen to their clipboard rather than a red sentence in a corner.
(test "a refused clipboard fills the window with an account of what was not read"
  (grants)
  (steps
    (settle)
    (click (role button :name "Start clipboard capture"))
    (settle)
    (expect-on-screen (role column :name "History placard"))
    (expect-on-screen (text "The clipboard was not granted"))
    (expect-on-screen (text-prefix "This window can read your clipboard only through a grant"))
    (expect-on-screen (text "Not reading your clipboard"))
    (expect-on-screen (role button :name "Start clipboard capture"))
    (screenshot "denied")
    (screenshot "denied-placard" :region (role column :name "History placard") :pad 8)))
