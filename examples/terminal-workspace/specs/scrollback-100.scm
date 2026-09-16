(test "ordinary terminal output scales scrollback"
  (grants
    (process test-program))
  (benchmark :warmups 1 :samples 3 :iterations 2 :scale 100 :initial-size 0 :change-size 100)
  (steps
    (click (role button :name "New terminal"))
    (await-task)
    (await-task)
    (replace-text (role textbox :name "Terminal command") "lines:100")
    (submit (role textbox :name "Terminal command"))
    (await-task)
    (mark-metrics)
    (await-task)
    (expect-count (text-prefix "line-") 100)
    (click (role button :name "Stop terminal"))
    (await-task)
    (await-task)
    (expect-processes 0)))
