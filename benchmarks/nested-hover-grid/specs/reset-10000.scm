(test "Nested local reset among 10000 cells"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Create 10000 cells"))
    (expect-count (button-prefix "Cell ") 10000)
    (hover-enter (role button :name "Cell 1"))
    (hover-exit (role button :name "Cell 1"))
    (mark-metrics)
    (await-task)
    (expect-background (role button :name "Cell 1") 0x263247)
    (expect-background (role button :name "Cell 2") 0x263247)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :ancestor-invalidations 7 :registry-visits 0 :projection-gets 22 :projection-sets 8)))
