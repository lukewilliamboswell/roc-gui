;; The inspector beside every view (§6): a divider resizes it by pointer or
;; keyboard and folds it away, a drag renders the window alone, and pinning it
;; keeps a view's selection beside every other view.
(test "the inspector resizes, collapses, and pins"
  (grants
    (file "fixture/captures/database-browser-scale-100.rgstats"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (expect-value (role separator :name "Inspector divider") "360")
    (expect-visible (text "INSPECTOR · Overview"))
    (expect-visible (text "Overview has nothing to inspect. Pin the inspector on a view to keep its selection beside every other."))
    ; the inspector is the sized pane after the divider, so moving the divider
    ; 100 pixels towards the start widens it by 100
    (drag (role separator :name "Inspector divider") 2 300 -98 300)
    (expect-value (role separator :name "Inspector divider") "460")
    ; the size is the window's own: every view, the tabs, and the inspector
    ; are kept
    (expect-component-work :rendered 1 :skipped 7 :mounted 0 :retired 0)
    (focus (role separator :name "Inspector divider"))
    (key "left")
    (expect-value (role separator :name "Inspector divider") "476")
    (key "home")
    (expect-value (role separator :name "Inspector divider") "1100")
    (key "end")
    (expect-value (role separator :name "Inspector divider") "240")
    (click (role button :name "Interactions"))
    (click (role button :name "Cycle r4 #7"))
    (await-task)
    (expect-visible (within (role column :name "Inspector") (text "CYCLE r4 #7 · task · replace · measured")))
    ; unpinned, the inspector follows the view
    (click (role button :name "Memory"))
    (expect-visible (text "INSPECTOR · Memory"))
    (expect-not-visible (text "CYCLE r4 #7 · task · replace · measured"))
    (click (role button :name "Interactions"))
    (click (role button :name "Pin inspector"))
    ; pinned, it keeps the cycle beside another view
    (click (role button :name "Memory"))
    (expect-visible (text "INSPECTOR · Interactions"))
    (expect-visible (within (role column :name "Inspector") (text "CYCLE r4 #7 · task · replace · measured")))
    (click (role button :name "Unpin inspector"))
    (expect-visible (text "INSPECTOR · Memory"))
    ; folded away, the inspector keeps its size to come back to
    (click (role button :name "Hide inspector"))
    (expect-value (role separator :name "Inspector divider") "collapsed")
    (expect-not-visible (role column :name "Inspector"))
    (focus (role separator :name "Inspector divider"))
    (key "enter")
    (expect-value (role separator :name "Inspector divider") "240")
    (expect-visible (role column :name "Inspector"))))
