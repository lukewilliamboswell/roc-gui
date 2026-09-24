; The divider between split workspaces is the application's size: a drag, the
; arrow keys, Home and End ask for one within its bounds, a drag past half the
; minimum folds the secondary workspace away without unmounting it, and Enter
; brings it back as it was.
(test "the workspace divider resizes by pointer and keyboard, and collapses"
  (steps
    (click (role button :name "Split workspace"))
    (expect-value (role separator :name "Workspace divider") "440")
    (replace-text (within (role column :name "Secondary workspace") (role textbox :name "Search terminal")) "needle")
    (submit (within (role column :name "Secondary workspace") (role textbox :name "Search terminal")))
    ; The secondary workspace is the sized pane and sits after the divider, so
    ; moving the divider 100 pixels towards the start widens it by 100.
    (drag (role separator :name "Workspace divider") 3 200 -97 200)
    (expect-value (role separator :name "Workspace divider") "540")
    ; The divider's size is the root's state, and neither workspace compares
    ; its input, so both render again with their terminals.
    (expect-component-work :rendered 5 :compared 0 :skipped 0 :mounted 0 :retired 0)
    ; A drag that asks for the size the divider already shows asks nothing.
    (drag (role separator :name "Workspace divider") 3 200 3 260)
    (expect-value (role separator :name "Workspace divider") "540")
    (focus (role separator :name "Workspace divider"))
    (key "right")
    (expect-value (role separator :name "Workspace divider") "524")
    (key "left")
    (key "left")
    (expect-value (role separator :name "Workspace divider") "556")
    (key "end")
    (expect-value (role separator :name "Workspace divider") "240")
    (key "home")
    (expect-value (role separator :name "Workspace divider") "720")
    (drag (role separator :name "Workspace divider") 3 200 1200 200)
    (expect-value (role separator :name "Workspace divider") "collapsed")
    (expect-component-work :rendered 5 :compared 0 :skipped 0 :mounted 0 :retired 0)
    (expect-not-visible (role column :name "Secondary workspace"))
    (expect-visible (role column :name "Primary workspace"))
    (key "enter")
    (expect-value (role separator :name "Workspace divider") "720")
    (expect-visible (within (role column :name "Secondary workspace") (text "filter \"needle\"")))
    (expect-visible (within (role column :name "Primary workspace") (text "filter off")))))
