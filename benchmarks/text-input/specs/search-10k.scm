(test "Settings search: 10,000 settings"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10000 :initial-size 100 :change-size 9900)
  (steps
    (click (role button :name "Load 10000 settings"))
    (expect-count (text-prefix "Setting ") 10000)
    (mark-metrics)
    (replace-text (role textbox :name "Search settings") "Privacy")
    (expect-count (text-prefix "Setting ") 2500)))
