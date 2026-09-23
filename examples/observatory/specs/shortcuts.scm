;; Keyboard shortcuts (US-38). Ctrl+1 to Ctrl+9 show the views in the rail's
;; order. In Interactions, J and K inspect the next and the previous cycle of
;; the list, slowest first, bringing it into view, and I moves keyboard focus
;; into the inspector. Each is declared by the part of the window it acts on,
;; so a key that changes the inspector renders the view and the inspector and
;; leaves the rest in place.
(test "shortcuts switch views and walk the slowest cycles"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (key "ctrl-7")
    (expect-visible (role column :name "Measurement families"))
    (expect-count (shortcut "j") 0)
    (key "ctrl-2")
    (expect-visible (text "TRIGGERS · measured · by median · warmups excluded"))
    (expect-count (shortcut "j") 1)
    (key "j")
    (await-task)
    (expect-visible (within (role column :name "Inspector title") (text-prefix "CYCLE r")))
    (expect-count (within (role virtual-list :name "Cycles") (role button :name "Cycle r4 #7")) 1)
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (key "j")
    (await-task)
    (expect-not-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (key "k")
    (await-task)
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (key "i")
    (expect-component-work :rendered 2 :mounted 0 :retired 0)
    (expect-focused (role button :name "Show step"))
    ; Every live element is asked for a chord that encloses no focus: the
    ; window's twelve shortcuts, and Interactions' three while it is shown.
    (expect-keyboard-counters 6 6 70 1)
    ; the shortcuts rest while the palette is open over them
    (key "ctrl-k")
    (key "alt-left")
    (key "ctrl-7")
    (expect-visible (role dialog :name "Command palette"))
    (expect-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (expect-keyboard-counters 9 7 75 1)))
