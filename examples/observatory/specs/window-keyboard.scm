;; The keyboard in the real window. Ctrl+K opens the palette with its query
;; focused, typed characters go to the query rather than to any shortcut, and
;; Enter chooses the highlighted result. Ctrl+2 shows Interactions, J inspects
;; the slowest cycle, I moves focus into the inspector, and Alt+Left returns
;; to the place before. Hovering a `—` shows why its value is absent.
(test "the keyboard drives Observatory in the window"
  (grants
    (directory "fixture/captures")
    (clipboard fixture))
  (steps
    (settle)
    (click (role button :name "Open folder"))
    (await-task)
    (settle)
    (key "ctrl-k")
    (settle)
    (expect-on-screen (role dialog :name "Command palette"))
    (expect-focused (role textbox :name "Palette query"))
    (type "scale 100")
    (settle)
    (expect-value (role textbox :name "Palette query") "scale 100")
    (expect-count (button-prefix "Palette ") 1)
    (screenshot "palette")
    (key "enter")
    (await-task)
    (settle)
    (expect-not-visible (role dialog :name "Command palette"))
    (expect-on-screen (role row :name "Capture bar"))
    (key "ctrl-2")
    (settle)
    (expect-on-screen (role virtual-list :name "Cycles"))
    (key "j")
    (await-task)
    (settle)
    (expect-visible (role column :name "Inspector title"))
    (key "i")
    (settle)
    (expect-focused (role button :name "Show step"))
    (scroll (role scroll :name "Inspector scroll") :to (role row :name "Waterfall gpui apply"))
    (settle)
    (click (role button :name "Copy Waterfall"))
    (await-task)
    (settle)
    (expect-on-screen (role row :name "Copied"))
    (screenshot "inspected-by-keyboard")
    (hover-enter (role button :name "Why gpui_application"))
    (await-count (role tooltip :name "gpui_application not_recorded: semantic headless execution does not instantiate GPUI views") 1)
    (settle)
    (screenshot "why-absent")
    (key "alt-left")
    (settle)
    (expect-on-screen (text "Press a cycle to inspect it."))
    ; the nine characters typed into the query were offered and left to it;
    ; Enter went to the query itself, and the five chords were answered, each
    ; compared with the shortcuts of the regions around focus and then with
    ; the window's. The folder is remembered, so the start page the palette
    ; closes over lists it, and focus does not come back to the inspector's
    ; divider, whose own keys a chord would be compared with first
    (expect-keyboard-counters 14 5 12 1)))
