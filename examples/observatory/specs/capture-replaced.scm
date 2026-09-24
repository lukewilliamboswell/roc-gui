;; A capture replaced in its folder (US-34). The folder is a private copy, and
;; `replace-file` moves another capture over the open one's name, as a person
;; does after recording again. The folder's watch reports the name, the folder
;; is listed again, and the new capture identity says the file now holds a
;; different capture. Reloading reads it where the person was: the view, the
;; trigger filter, and the inspected cycle, found again by run, trigger, and
;; ordinal.
(test "a replaced capture is offered for reloading and reloads in place"
  (grants
    (directory copy "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture counter-counting.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Capture bar") (text "✓ final")))
    (expect-not-visible (within (role row :name "Capture bar") (text "● live")))
    (click (role button :name "Interactions"))
    (click (role button :name "Filter click replace"))
    (await-task)
    (click (role button :name "Cycle r1 #2"))
    (await-task)
    (expect-visible (text "CYCLE r1 #2 · click · replace · measured"))
    (expect-watch-counters 1 _ 0 0 1)
    (replace-file "counter-counting.rgstats" "fixture/captures/counter-independence.rgstats")
    ; The watch reports the capture's name, and the folder is listed again.
    (await-task)
    (await-task)
    (expect-visible (within (role row :name "Capture bar") (role button :name "Reload capture")))
    (expect-visible (within (role row :name "Capture bar") (text "Capture changed")))
    ; Until it is reloaded, the capture on screen is still the one read.
    (expect-visible (text "CYCLE r1 #2 · click · replace · measured"))
    (click (role button :name "Reload capture"))
    (await-task)
    (expect-not-visible (role button :name "Reload capture"))
    (expect-not-visible (text "Capture changed"))
    (expect-visible (text "CYCLES · measured · click · replace · slowest first · 3"))
    (expect-visible (text "CYCLE r1 #2 · click · replace · measured"))
    (click (role button :name "Health"))
    (expect-visible (within (role panel :name "Identity") (text "spec_name = Counter cards move only their own tally")))
    ; One watch, of the folder, is held throughout: the replaced capture was
    ; finalised, so it is not watched itself.
    (expect-watch-counters 1 _ 0 0 1)))
