;; Photographs the start page (W0) with its recent list: captures and a folder
;; that reopen, and entries the host found missing or replaced, each with its
;; reason and a way to forget it.
(test "the window shows the start page's recent list"
  (grants
    (directory copy "fixture/captures")
    (recents
      (copied "counter-counting.rgstats")
      "fixture/compare"
      (copied "database-browser-browse.rgstats")
      (copied "counter-independence.rgstats")
      "fixture/scale-10"))
  (steps
    (settle)
    (expect-on-screen (role virtual-list :name "Recent"))
    (expect-on-screen (role button :name "Recent counter-counting.rgstats"))
    (screenshot "recent")
    (remove-file "database-browser-browse.rgstats")
    (replace-file "counter-independence.rgstats" "fixture/captures/counter-counting.rgstats")
    (click (role button :name "Recent counter-independence.rgstats"))
    (await-task)
    (settle)
    (expect-on-screen (within (role row :name "Recent row counter-independence.rgstats") (text "Another file has taken its place, so it is not the one you opened.")))
    (expect-on-screen (within (role row :name "Recent row database-browser-browse.rgstats") (text "Nothing is at its place any more.")))
    (screenshot "unavailable")
    (screenshot "unavailable-rows" :region (role column :name "Recent table") :pad 8)))
