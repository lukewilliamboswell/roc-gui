(test "Settings search: 100 settings"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 100 :change-size 75)
  (steps
    (expect-count (text-prefix "Setting ") 100)
    (mark-metrics)
    (replace-text (role textbox :name "Search settings") "Privacy")
    (expect-count (text-prefix "Setting ") 25)))
