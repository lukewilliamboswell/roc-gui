;; A scaling set is chosen from the folder: one executable's benchmark at 100,
;; 1,000, and 10,000 rows. Each trigger's mean work is shown as an observed
;; ratio against the scale ratio, with a verdict only where every step has
;; evidence, beside the count assertions each capture made. A set that mixes
;; in a contended run, or two captures of one scale, is refused with its key.
(test "a scaling set shows each trigger's growth and refuses what it cannot compare"
  (grants
    (directory "fixture/compare"))
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture browse-100.rgstats"))
    (await-task)
    (click (role button :name "Scaling"))
    (expect-visible (text "CHOSEN 0: none"))
    (click (role button :name "Scaling set browse-100.rgstats"))
    ; choosing is the Scaling view's own change: it renders that view and its
    ; list of captures, and nothing else
    (expect-component-work :rendered 2 :mounted 0 :retired 0)
    (click (role button :name "Scaling set browse-1k.rgstats"))
    (click (role button :name "Scaling set browse-10k.rgstats"))
    (expect-visible (text "CHOSEN 3: browse-100.rgstats · browse-1k.rgstats · browse-10k.rgstats"))
    (click (role button :name "Build scaling set"))
    (await-task)
    ; each capture of the set is read through a connection of its own
    (expect-sqlite-counters 4 10 96)
    (expect-visible (within (role row :name "Scaling verdict") (text "✓ 3 captures at scales 100 · 1000 · 10000")))
    (expect-count (within (role column :name "Scaling gate") (text "✓")) 14)
    (expect-visible (within (role row :name "Scale check browse-10k.rgstats") (text "✓")))
    (expect-visible (within (role row :name "Scale check browse-10k.rgstats") (text "3")))
    (expect-count (within (role column :name "Scale checks") (text "✓")) 3)
    (expect-visible (within (role column :name "Scaling ratios") (text "100→1000 (10.0×)")))
    (expect-visible (within (role column :name "Scaling ratios") (text "1000→10000 (10.0×)")))
    ; allocation is deterministic: the virtualized list allocates the same at
    ; every scale
    (expect-count (within (role row :name "Ratio task span allocated bytes") (text "1.0×")) 2)
    (expect-visible (within (role row :name "Ratio task span allocated bytes") (text "sub-linear")))
    ; every timing step has evidence, so every timing metric has a verdict
    (expect-not-visible (within (role row :name "Ratio task callback") (text "—")))
    (expect-not-visible (within (role row :name "Ratio click graph apply") (text "—")))
    (expect-visible (role canvas-item :name "Point task callback 10000"))
    (expect-visible (within (role row :name "Scaling A/A verdict") (text "No A/A capture: ratios carry no noise band.")))
    ; a contended run fails isolation and job count, and repeats a scale
    (click (role button :name "Scaling set browse-100-jobs-2.rgstats"))
    ; a set read before the choice changed is not shown beside it
    (expect-visible (within (role row :name "Scaling verdict") (text "The chosen captures changed: press Build scaling set to read them.")))
    (expect-not-visible (role column :name "Scaling ratios"))
    (click (role button :name "Build scaling set"))
    (await-task)
    (expect-visible (within (role row :name "Scaling verdict") (text "✗ refused: timing_quality: browse-100-jobs-2.rgstats is partial-contended; a scaling set needs isolated timing")))
    (expect-visible (within (role row :name "Scaling gate job_count") (text "browse-100-jobs-2.rgstats ran 2 jobs; a scaling set needs 1")))
    (expect-visible (within (role row :name "Scaling gate benchmark_scale") (text "✗")))
    (expect-not-visible (role column :name "Scaling ratios"))
    ; an A/A repeat is a second capture of one scale
    (click (role button :name "Scaling set browse-100-jobs-2.rgstats"))
    (click (role button :name "Scaling set browse-100-aa.rgstats"))
    (click (role button :name "Build scaling set"))
    (await-task)
    (expect-visible (within (role row :name "Scaling verdict") (text "✗ refused: benchmark_scale: browse-100.rgstats shares scale 100 with another capture")))
    ; one capture is not a set
    (click (role button :name "Scaling set browse-100-aa.rgstats"))
    (click (role button :name "Scaling set browse-1k.rgstats"))
    (click (role button :name "Scaling set browse-10k.rgstats"))
    (click (role button :name "Build scaling set"))
    (await-task)
    (expect-visible (within (role row :name "Scaling verdict") (text "✗ refused: members: a set needs two or more captures, not 1")))))
