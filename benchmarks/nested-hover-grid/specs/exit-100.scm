(test "Nested local exit among 100 cells"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Create 100 cells"))
    (expect-count (button-prefix "Cell ") 100)
    (hover-enter (role button :name "Cell 1"))
    (mark-metrics)
    (hover-exit (role button :name "Cell 1"))
    (expect-background (role button :name "Cell 1") 0xD58AFF)
    (expect-background (role button :name "Cell 2") 0x263247)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :ancestor-invalidations 4 :registry-visits 1 :projection-gets 13 :projection-sets 5)))
