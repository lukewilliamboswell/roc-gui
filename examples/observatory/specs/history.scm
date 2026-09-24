;; Back and forward over jumps (US-36). Opening a cycle, its step, and a
;; palette target each remember the place left; Alt+Left and the Back button
;; return to it with its view, its selection, and its list where it was, and
;; Alt+Right goes forward again. A new jump forgets what was ahead.
(test "back and forward return over the places jumped between"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (expect-count (role button :name "Back") 1)
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (click (role button :name "Show step"))
    (await-task)
    (expect-visible (text "STEPS OF RUN 4 · 9"))
    (expect-visible (role panel :name "Focused step"))
    (key "alt-left")
    (await-task)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (expect-not-visible (role panel :name "Focused step"))
    ; the place before the cycle held the same run, so nothing is read again
    (key "alt-left")
    (expect-visible (text "Press a cycle to inspect it."))
    (key "alt-right")
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (click (role button :name "Forward"))
    (await-task)
    (expect-visible (role panel :name "Focused step"))
    (click (role button :name "Back"))
    (await-task)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    ; a new jump from here forgets the step ahead
    (key "ctrl-k")
    (replace-text (role textbox :name "Palette query") "view health")
    (submit (role textbox :name "Palette query"))
    (expect-visible (role column :name "Measurement families"))
    (key "alt-right")
    (expect-visible (role column :name "Measurement families"))
    (key "alt-left")
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))))
