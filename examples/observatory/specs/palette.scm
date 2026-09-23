;; The command palette (US-35) opens with Ctrl+K wherever focus is and finds
;; what is typed among commands, captures, views, and triggers, a run of
;; letters at a word's start first. It is a dialog: its query takes focus, Up
;; and Down move the highlight while focus is in it, Enter chooses the
;; highlighted result, and Escape closes it. Typing renders the palette alone.
(test "the command palette finds captures, views, and triggers by typing"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (expect-count (shortcut "ctrl-k") 1)
    (key "ctrl-k")
    (expect-visible (role dialog :name "Command palette"))
    (expect-focused (role textbox :name "Palette query"))
    (expect-visible (role button :name "Palette Command Open folder…"))
    (expect-visible (role button :name "Palette Capture database-browser-scale-100.rgstats"))
    (replace-text (role textbox :name "Palette query") "scale 100")
    (expect-component-work :rendered 1 :mounted 0 :retired 0)
    (expect-count (button-prefix "Palette ") 1)
    (submit (role textbox :name "Palette query"))
    (await-task)
    (expect-not-visible (role dialog :name "Command palette"))
    (expect-visible (role button :name "Interactions"))
    (key "ctrl-k")
    (replace-text (role textbox :name "Palette query") "view")
    (expect-count (button-prefix "Palette View ") 9)
    (expect-background (role row :name "Palette row View Overview") 0xe6eef5)
    (key "down")
    (expect-background (role row :name "Palette row View Overview") 0xffffff)
    (expect-background (role row :name "Palette row View Interactions") 0xe6eef5)
    (key "down")
    (key "up")
    (expect-background (role row :name "Palette row View Interactions") 0xe6eef5)
    (submit (role textbox :name "Palette query"))
    (expect-visible (text "TRIGGERS · measured · by median · warmups excluded"))
    (key "ctrl-k")
    (replace-text (role textbox :name "Palette query") "click")
    (expect-visible (role button :name "Palette Trigger click · replace · measured"))
    (click (role button :name "Palette Trigger click · replace · measured"))
    (await-task)
    (expect-not-visible (role dialog :name "Command palette"))
    (expect-visible (text-prefix "CYCLES · measured · click · replace · slowest first"))
    (key "ctrl-k")
    (press-key Escape)
    (expect-not-visible (role dialog :name "Command palette"))
    ; Seven chords, each answered. Ctrl+K is the window's first shortcut, so
    ; it compares one, and three more while Interactions declares J, K, and
    ; I; Down and Up are the palette's own, asked first with focus in it.
    (expect-keyboard-counters 7 7 14 0)))
