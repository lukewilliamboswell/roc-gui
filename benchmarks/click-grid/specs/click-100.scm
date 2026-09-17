(test "Click grid: stationary press among 100 cells"
  (benchmark :warmups 2 :samples 7 :iterations 4 :scale 100 :initial-size 100 :change-size 1)
  (steps
    (click (role button :name "Create 100 cells"))
    (expect-count (button-prefix "Cell ") 100)
    (mark-metrics)
    (click (role button :name "Cell 50"))
    (expect-background (role button :name "Cell 50") 0xF59E0B)
    (expect-background (role button :name "Cell 49") 0x263247)
    (expect-background (role button :name "Cell 51") 0x263247)
    (expect-patch :kind replace :staged 2 :removed 2)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1 :projection-gets 3 :projection-sets 1)))
