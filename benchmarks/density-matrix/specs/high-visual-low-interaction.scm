(test "Density matrix: high visual payload and low interaction density"
  (benchmark :warmups 2 :samples 7 :iterations 1 :scale 25 :initial-size 50 :change-size 1)
  (steps
    (click (role button :name "Show high visual low interaction"))
    (expect-count (text-prefix "Node ") 2500)
    (expect-count (button-prefix "Run action ") 25)
    (mark-metrics)
    (click (role button :name "Run action 1"))
    (expect-count (role button :name "Action 1 ran 1 time") 1)
    (expect-count (role button :name "Run action 2") 1)
    (expect-component-work :rendered 1 :compared 0 :mounted 0 :retired 0 :registry-visits 1 :projection-sets 1)))
