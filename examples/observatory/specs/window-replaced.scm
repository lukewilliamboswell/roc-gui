;; Drives the real window through a capture replaced in its folder (US-34),
;; photographing the capture bar's offer to reload and the capture read again
;; in the same place.
(test "the window offers a replaced capture for reloading"
  (grants
    (directory copy "fixture/captures"))
  (steps
    ; The smallest window the suite supports, as a small laptop or CI display gives.
    (resize 1024 656)
    (settle)
    (click (role button :name "Open folder"))
    (await-count (role virtual-list :name "Captures") 1)
    (click (role button :name "Capture counter-counting.rgstats"))
    (await-count (role tab :name "counter-counting.rgstats") 1)
    (click (role button :name "Interactions"))
    (scroll (role scroll :name "Interactions scroll") :to (role button :name "Cycle r1 #2"))
    (settle)
    (click (role button :name "Cycle r1 #2"))
    (await-count (text "CYCLE r1 #2 · click · replace · measured") 1)
    (replace-file "counter-counting.rgstats" "fixture/captures/counter-independence.rgstats")
    (await-count (role button :name "Reload capture") 1)
    (settle)
    (expect-on-screen (within (role row :name "Capture bar") (text "Capture changed")))
    (screenshot "changed")
    (click (role button :name "Reload capture"))
    (await-count (role button :name "Reload capture") 0)
    (settle)
    (expect-visible (text "CYCLE r1 #2 · click · replace · measured"))
    (screenshot "reloaded")))
