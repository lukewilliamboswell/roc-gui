; The root renders one component directly, so the root's node is the
; component's. A press rebuilds the component and replaces that node, and a
; later reload must replace the node the graph holds, not the one the first
; mount made.
(test "A reload after the root component rebuilds replaces the current root"
  (steps
    (click (role button :name "Press"))
    (expect-visible (text "Pressed 1 times"))
    (reload)
    (expect-visible (text "Edit this file while the page runs"))
    (expect-visible (text "Pressed 1 times"))
    (click (role button :name "Press"))
    (expect-visible (text "Pressed 2 times"))
    (reload)
    (expect-visible (text "Pressed 2 times"))))
