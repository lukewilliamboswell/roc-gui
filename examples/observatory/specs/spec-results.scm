;; Each run of a benchmark is selectable, and its steps are listed with their
;; result, duration, and expected and observed counts.
(test "spec results list runs and the steps of the selected run"
  (grants
    (directory "fixture/captures"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture database-browser-scale-100.rgstats"))
    (await-task)
    (click (role button :name "Spec"))
    (expect-count (within (role row :name "Run") (button-prefix "Run ")) 4)
    (expect-count (within (role column :name "Runs") (text "pass")) 4)
    (expect-visible (within (role column :name "Runs") (text "warmup")))
    (expect-visible (text "STEPS OF RUN 1 · 9"))
    (expect-count (within (role virtual-list :name "Steps") (text-prefix "Step line ")) 9)
    (expect-visible (within (role virtual-list :name "Steps") (text "expect-count")))
    (expect-visible (within (role virtual-list :name "Steps") (text "count 100 / 100")))
    (click (role button :name "Run 3"))
    (await-task)
    (expect-visible (text "STEPS OF RUN 3 · 9"))
    (expect-count (within (role virtual-list :name "Steps") (text-prefix "Step line ")) 9)))
