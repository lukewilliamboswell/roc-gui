;; Chord hints (US-38). Every hint names a chord as its shortcut declares it,
;; and the host spells it as the person presses it: Cmd on macOS, Ctrl on
;; Linux and Windows. The header names the palette's chord, and each view in
;; the palette names the chord that shows it.
(test "every chord hint is spelled as the platform presses it"
  (grants
    (directory "fixture/captures"))
  (steps
    (expect-count (within (role row :name "Palette hint") (chord "secondary-k")) 1)
    (expect-visible (within (role row :name "Palette hint") (text "commands")))
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (key "secondary-2")
    (key "secondary-k")
    (expect-visible (role dialog :name "Command palette"))
    (expect-count (within (role row :name "Palette row View Overview") (chord "secondary-1")) 1)
    (expect-count (within (role row :name "Palette row View Interactions") (chord "secondary-2")) 1)
    ; Nothing was jumped between, so Back and Forward are not offered, and
    ; neither is their chord.
    (expect-count (chord "alt-left") 0)
    (expect-count (chord "alt-right") 0)))
