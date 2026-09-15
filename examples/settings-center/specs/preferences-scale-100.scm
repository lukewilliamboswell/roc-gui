(test "save a realistic 100-byte profile note"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)
  (steps
    (replace-text (role textarea :name "Profile notes") "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
    (mark-metrics)
    (click (role button :name "Apply profile") )
    (await-task)
    (expect-value-bytes (role textarea :name "Profile notes") 100)))
