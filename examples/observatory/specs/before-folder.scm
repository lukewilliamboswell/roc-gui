(test "the first frame offers only the folder choice"
  (grants
    (directory "fixture/captures"))
  (steps
    (expect-visible (role button :name "Open folder"))
    (expect-visible (text "no folder granted"))
    (expect-visible (text "choose a folder of captures"))
    (expect-visible (text "no capture open"))
    (expect-visible (text "Choose a folder of .rgstats captures, such as a benchmark output directory."))
    (expect-not-visible (role virtual-list :name "Captures"))
    (expect-not-visible (role row :name "Capture bar"))
    (expect-sqlite-counters 0 0 0)))
