;; The start page lists what was opened before (US-3): remembered captures and
;; folders, most recent first, read as the window opens. The list is the
;; host's, provisioned here for the run. Its captures are children of a
;; private copy of a folder, so a step can delete one and move another capture
;; over a second, as a person tidying a benchmark folder does. Reopening
;; either is refused with the reason the host found, the list is read again
;; with both reasons shown, and an entry can be forgotten. An entry that is
;; still what was remembered reopens as a new grant, remembered again.
(test "recent captures and folders reopen, and say why when they cannot"
  (grants
    (directory copy "fixture/captures")
    (recents
      (copied "counter-counting.rgstats")
      (copied "database-browser-browse.rgstats")
      (copied "counter-independence.rgstats")
      "fixture/compare"))
  (steps
    (expect-rows (role virtual-list :name "Recent") :count 4 :first 0 :mounted 4)
    (expect-visible (text "RECENT · 4"))
    (expect-before (role button :name "Recent counter-counting.rgstats") (role button :name "Recent compare"))
    (expect-visible (within (role row :name "Recent row compare") (text "folder")))
    (expect-visible (within (role row :name "Recent row counter-counting.rgstats") (text "capture")))
    (remove-file "database-browser-browse.rgstats")
    (replace-file "counter-independence.rgstats" "fixture/captures/counter-counting.rgstats")
    ; the list was read as the window opened; reopening checks again
    (click (role button :name "Recent database-browser-browse.rgstats"))
    (await-task)
    (expect-visible (within (role panel :name "Capture error") (text "Could not reopen database-browser-browse.rgstats")))
    (expect-visible (within (role panel :name "Capture error") (text "Nothing is at its place any more.")))
    (expect-visible (within (role row :name "Recent row database-browser-browse.rgstats") (text "Nothing is at its place any more.")))
    (expect-visible (within (role row :name "Recent row counter-independence.rgstats") (text "Another file has taken its place, so it is not the one you opened.")))
    (expect-grants)
    (expect-recent-counters 0 0 1 0 4)
    (click (role button :name "Forget database-browser-browse.rgstats"))
    (expect-rows (role virtual-list :name "Recent") :count 3)
    (expect-not-visible (role row :name "Recent row database-browser-browse.rgstats"))
    ; a folder reopens and is listed, and becomes the most recent entry
    (click (role button :name "Recent compare"))
    (await-task)
    (expect-visible (role button :name "Capture browse-100.rgstats"))
    (expect-before (role button :name "Recent compare") (role button :name "Recent counter-counting.rgstats"))
    ; a capture reopens as a new grant, remembered for the next run
    (click (role button :name "Recent counter-counting.rgstats"))
    (await-task)
    (expect-selected (role tab :name "counter-counting.rgstats"))
    (expect-visible (within (role row :name "Capture bar") (text "schema 25")))
    (expect-grants
      "directory provisioned/consent-only root read,list,derive remembered"
      "document provisioned/consent-only root read,derive remembered"
      "sqlite provisioned/consent-only derived read,derive remembered"
      "watch provisioned/consent-only derived read remembered")
    (expect-recent-counters 2 2 1 1 3)))
