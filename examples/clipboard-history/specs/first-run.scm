; The first thing this window has to be able to say is that it has not read
; anything. "Never asked" and "asked and refused" are different facts about a
; person's data and get different sentences; the resting state after a pause is
; a third. Each of them names what would change it.
(test "a fresh window states that it has read nothing, and says so differently after a refusal"
  (grants
    (clipboard fixture))
  (steps
    (expect-subscriptions 0)
    (expect-visible (text "Nothing has been read yet"))
    (expect-visible (text "Not reading your clipboard"))
    (expect-visible (text "Capture is off"))
    (expect-not-visible (text "Watching for changes"))
    ; Nothing was read to reach that state.
    (expect-clipboard-counters 0 0 0 0)
    (click (role button :name "Start clipboard capture"))
    (expect-visible (text "Watching for changes"))
    (expect-visible (text "Reading your clipboard · nothing leaves this window"))
    (expect-not-visible (text "Nothing has been read yet"))
    ; A pause is a third state again: the grant was held, so the sentence is
    ; about what is not happening now rather than what has never happened.
    (click (role button :name "Pause clipboard capture"))
    (await-task)
    (expect-visible (text "Capture is paused"))
    (expect-visible (text "Not reading your clipboard"))
    (expect-not-visible (text "Nothing has been read yet"))
    (expect-not-visible (text "Watching for changes"))))
