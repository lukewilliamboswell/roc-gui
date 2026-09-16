(test "history presses at their boundaries change nothing"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Open project"))
    (await-task)
    (expect-visible (text "fixture"))
    (click (role button :name "Breadcrumb root"))
    (expect-patch :kind no_change :staged 0 :removed 0)
    (expect-visible (text "fixture"))
    (click (role button :name "Open folder nested"))
    (await-task)
    ; the path is a strip of segments now, not one joined string
    (expect-visible (text "nested"))
    (expect-visible (text "›"))
    (click (role button :name "Select File: item.txt"))
    (expect-visible (text "Selected: item.txt"))
    (click (role button :name "Back"))
    (expect-not-visible (role panel :name "Selection details"))
    (expect-visible (text "fixture"))
    (click (role button :name "Forward"))
    ; the path is a strip of segments now, not one joined string
    (expect-visible (text "nested"))
    (expect-visible (text "›"))
    (expect-file-opens 1)))
