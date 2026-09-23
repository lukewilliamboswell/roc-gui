;; An A/A capture draws a noise band over a scaling set: the same executable
;; run again at one of the set's scales. A step ratio within the band of 1 is
;; marked within noise. An A/A capture must pass the comparability gate
;; against the member of its scale, and must have a member at its scale.
(test "an A/A capture marks the scaling ratios that are noise"
  (grants
    (directory "fixture/compare"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture browse-100.rgstats"))
    (await-task)
    (click (role button :name "Scaling"))
    (click (role button :name "Scaling set browse-1k.rgstats"))
    (click (role button :name "Scaling set browse-10k.rgstats"))
    (click (role button :name "Build scaling set"))
    (await-task)
    ; an A/A capture at a scale the set does not hold bounds nothing
    (click (role button :name "Scaling A/A browse-100-aa.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Scaling A/A verdict") (text "✗ A/A browse-100-aa.rgstats refused: benchmark_scale: no capture of the set has scale 100")))
    (click (role button :name "Scaling set browse-100.rgstats"))
    (click (role button :name "Build scaling set"))
    (await-task)
    (expect-visible (within (role row :name "Scaling A/A verdict") (text "✓ A/A browse-100-aa.rgstats bounds the set against browse-100.rgstats")))
    ; allocation repeats exactly, so its band is zero and its unchanged ratio
    ; lies within it
    (expect-count (within (role row :name "Ratio task span allocated bytes") (text "1.0× within noise")) 2)
    (expect-count (within (role row :name "Ratio click span allocated bytes") (text "1.0× within noise")) 2)
    ; the scale verification stays beside the ratios
    (expect-count (within (role column :name "Scale checks") (text "✓")) 3)
    ; a contended A/A capture fails the comparability gate
    (click (role button :name "Scaling A/A browse-100-jobs-2.rgstats"))
    (await-task)
    (expect-visible (within (role row :name "Scaling A/A verdict") (text "✗ A/A browse-100-jobs-2.rgstats refused: job_count differs: 1 against 2")))
    (expect-not-visible (within (role column :name "Scaling ratios") (text-prefix "1.0× within")))))
