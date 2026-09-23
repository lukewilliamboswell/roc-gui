;; Observatory follows the desktop's light or dark scheme (US-39) and the
;; palette chooses one over it. Every colour is an adaptive pair the window
;; resolves when it paints, so a change of scheme repaints without rendering.
(test "the window follows the system theme, and the palette chooses one over it"
  (grants
    (directory "fixture/captures")
    (theme dark))
  (steps
    (expect-theme dark)
    (expect-background (role row :name "Observatory header") 0x191d22)
    ; the desktop turns light, and the window with it
    (system-theme light)
    (expect-theme light)
    (expect-background (role row :name "Observatory header") 0xeceef1)
    (click (role button :name "Open folder"))
    (await-task)
    (key "ctrl-k")
    (replace-text (role textbox :name "Palette query") "theme dark")
    (expect-visible (role button :name "Palette Command Theme: dark"))
    (click (role button :name "Palette Command Theme: dark"))
    (await-task)
    (expect-not-visible (role dialog :name "Command palette"))
    (expect-theme dark)
    (expect-background (role row :name "Observatory header") 0x191d22)
    ; a chosen scheme outlasts the desktop's changes
    (system-theme dark)
    (system-theme light)
    (expect-theme dark)
    (key "ctrl-k")
    (replace-text (role textbox :name "Palette query") "theme follow")
    (click (role button :name "Palette Command Theme: follow the system"))
    (await-task)
    (expect-theme light)
    (expect-background (role row :name "Observatory header") 0xeceef1)))
