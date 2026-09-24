(test "the first frame offers the capture and folder choices"
  (grants
    (directory "fixture/captures"))
  (steps
    (expect-visible (role button :name "Open capture"))
    (expect-visible (role button :name "Open folder"))
    (expect-visible (text "no folder granted"))
    (expect-visible (text "choose a folder of captures"))
    (expect-visible (text "no capture open"))
    (expect-visible (text "Open one .rgstats capture, or choose a folder of them, such as a benchmark output directory."))
    (expect-not-visible (role virtual-list :name "Captures"))
    (expect-not-visible (role row :name "Capture bar"))
    (expect-sqlite-counters 0 0 0)
    (expect-document-counters 0 0 0 0 0 0)))
