; The real pointer presses the divider, drags it with the button held, and
; releases: the secondary workspace follows it, folds away past half its
; minimum, and comes back to the keyboard.
(test "the workspace divider follows the window's own pointer"
  (steps
    (settle)
    (click (role button :name "Split workspace"))
    (expect-on-screen (role separator :name "Workspace divider"))
    (expect-bounds (role column :name "Secondary workspace") :min-width 435 :max-width 445)
    (screenshot "split")
    (drag (role separator :name "Workspace divider") 3 200 -97 200)
    (expect-value (role separator :name "Workspace divider") "540")
    (expect-bounds (role column :name "Secondary workspace") :min-width 535 :max-width 545)
    (expect-component-work :rendered 5 :compared 0 :skipped 0 :mounted 0 :retired 0)
    (screenshot "dragged")
    (focus (role separator :name "Workspace divider"))
    (key "right")
    (expect-value (role separator :name "Workspace divider") "524")
    (screenshot "focused")
    (drag (role separator :name "Workspace divider") 3 200 1200 200)
    (expect-value (role separator :name "Workspace divider") "collapsed")
    (expect-not-visible (role column :name "Secondary workspace"))
    (expect-on-screen (role separator :name "Workspace divider"))
    (screenshot "collapsed")
    (focus (role separator :name "Workspace divider"))
    (key "enter")
    (expect-value (role separator :name "Workspace divider") "524")
    (expect-on-screen (role column :name "Secondary workspace"))
    (screenshot "restored")))
