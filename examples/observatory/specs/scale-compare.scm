;; The scaling case for comparison and scaling: a benchmark output folder of
;; 1000 real captures. A baseline and a capture of it are compared, and the
;; A/A and scaling-set choosers list every capture of the folder, building only
;; the rows a screen shows, so choosing a capture costs the same at any folder
;; size.
(test "compare and choose a scaling set in a folder of 1000 captures"
  (grants
    (directory "fixture/scale-1000"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 1000 :initial-size 0 :change-size 1000)
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture run-0003.rgstats"))
    (await-task)
    (click (role button :name "Set as baseline"))
    (click (role button :name "Back to captures"))
    (click (role button :name "Capture run-0007.rgstats"))
    (await-task)
    (click (role button :name "Compare"))
    (expect-visible (within (role row :name "Comparability verdict") (text-prefix "⇒ comparable")))
    (expect-rows (role virtual-list :name "A/A captures") :count 1000 :first 0 :mounted 70)
    (click (role button :name "Scaling"))
    (expect-rows (role virtual-list :name "Scaling captures") :count 1000 :first 0 :mounted 70)
    (mark-metrics)
    (click (role button :name "Scaling set run-0003.rgstats"))
    ; the Scaling view and its list render, and the list rebuilds only the
    ; rows near its viewport
    (expect-component-work :rendered 2 :mounted 0 :retired 0)
    (expect-count (button-prefix "Scaling set ") 70)
    (expect-visible (text "CHOSEN 1: run-0003.rgstats"))))
