;; The keyboard in the real window: GPUI delivers each chord to the window's
;; root, which finds the list's shortcut in the mounted graph. End brings the
;; last of a million rows into view, and Up and Down move within it. With a
;; row button focused the list's shortcuts still answer, because a button
;; takes only Enter and Space for itself.
(test "Virtual list: the keyboard through a million rows in the window"
  (steps
    (resize 960 480)
    (settle)
    (click (role button :name "Provide 1000000 rows"))
    (settle)
    (key "end")
    (settle)
    (expect-visible (text "Selected: 999999"))
    (expect-on-screen (role button :name "Select virtual row 999999"))
    (expect-count (role button :name "Select virtual row 0") 0)
    (key "up")
    (key "up")
    (settle)
    (expect-visible (text "Selected: 999997"))
    (focus (role button :name "Select virtual row 999990"))
    (expect-focused (role button :name "Select virtual row 999990"))
    (key "down")
    (settle)
    (expect-visible (text "Selected: 999998"))
    (expect-keyboard-counters 4 4 9 0)
    (screenshot "moved-by-keyboard")
    (key "home")
    (settle)
    (expect-visible (text "Selected: 0"))
    (expect-on-screen (role button :name "Select virtual row 0"))
    (screenshot "first-row")))
