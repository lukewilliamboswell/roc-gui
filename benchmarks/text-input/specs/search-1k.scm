(test "Settings search: 1,000 settings"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 100 :change-size 900)
  (steps
    (click (role button :name "Load 1000 settings"))
    (expect-count (text-prefix "Setting ") 1000)
    (mark-metrics)
    (replace-text (role textbox :name "Search settings") "Privacy")
    (expect-count (text-prefix "Setting ") 250)))
