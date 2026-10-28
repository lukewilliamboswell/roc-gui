; A reload is the turn the host runs when a development session publishes a
; new application image. The new session renders the kept state from an empty
; component table, so it mounts both cards and retires nothing of its own; the
; host drops the old instances with the replaced root. The controls it mounts
; still dispatch.
(test "Counter keeps its tallies across a reload"
  (steps
    (click (role button :name "Left increment"))
    (click (role button :name "Right decrement"))
    (expect-visible (text "0"))
    (expect-visible (text "2"))
    (reload)
    (expect-component-work :rendered 3 :compared 0 :skipped 0 :mounted 2 :retired 0)
    (expect-visible (text "Counter"))
    (expect-visible (text "0"))
    (expect-visible (text "2"))
    (click (role button :name "Left increment"))
    (expect-visible (text "1"))
    (click (role button :name "Right increment"))
    (expect-visible (text "3"))))
