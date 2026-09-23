;; Captures dropped on the start page open (US-4): the drop is the grant, so
;; the case declares none. Each dropped capture is granted on its own, opens
;; in a tab of its own, and is remembered; a file of another type and a folder
;; dropped with them are named and refused.
(test "captures dropped on the start page open, each in its own tab"
  (grants)
  (steps
    (expect-not-visible (role virtual-list :name "Recent"))
    (drop (role drop-target :name "Observatory")
      "fixture/captures/counter-counting.rgstats"
      "fixture/captures/notes.txt"
      "fixture/captures/counter-independence.rgstats"
      "fixture/compare")
    (await-task)
    (expect-count (role tab :name "counter-counting.rgstats") 1)
    (expect-selected (role tab :name "counter-independence.rgstats"))
    (expect-visible (within (role row :name "Capture bar") (text "schema 25")))
    (expect-visible (within (role panel :name "Capture error") (text "Not opened: notes.txt, compare")))
    (expect-drop-counters 1 2 2)
    (expect-grants
      "document drop/consent-only root read,derive remembered"
      "document drop/consent-only root read,derive remembered"
      "sqlite drop/consent-only derived read,derive remembered"
      "sqlite drop/consent-only derived read,derive remembered")
    (expect-recent-counters 2 0 0 0 2)
    ; the start page now lists both, the last opened first
    (click (role button :name "Back to captures"))
    (expect-rows (role virtual-list :name "Recent") :count 2)
    (expect-before (role button :name "Recent counter-independence.rgstats") (role button :name "Recent counter-counting.rgstats"))
    ; a drop of nothing Observatory opens says so, and grants nothing
    (drop (role drop-target :name "Observatory") "fixture/captures/notes.txt")
    (expect-visible (within (role panel :name "Capture error") (text "Not opened: notes.txt")))
    (expect-drop-counters 2 2 3)))
