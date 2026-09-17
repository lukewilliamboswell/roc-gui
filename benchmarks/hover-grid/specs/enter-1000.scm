(test "Hover grid: local enter among 1000 cells"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 1000 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Create 1000 cells"))
    (expect-count (button-prefix "Cell ") 1000)
    (mark-metrics)
    (hover-enter (role button :name "Cell 50"))
    (expect-background (role button :name "Cell 50") 0x66E0FF)
    (expect-background (role button :name "Cell 49") 0x263247)
    (expect-background (role button :name "Cell 51") 0x263247)
    (expect-patch :kind replace :staged 2 :removed 2)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1 :projection-gets 3 :projection-sets 1)))
