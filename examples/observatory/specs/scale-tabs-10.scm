;; The scaling case for capture tabs: 10 captures open at once, one tab
;; each, opened through the folder list as a person would. Switching from
;; the last tab back to the first mounts that capture's view from what its
;; tab held and reads nothing; its work does not grow with the tabs open.
(test "switch among 10 open captures"
  (grants
    (directory "fixture/scale-10"))
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 10 :initial-size 10 :change-size 1)
  (steps
    (click (role button :name "Open folder"))
    (await-task)
    (click (role button :name "Capture run-0000.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0001.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0002.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0003.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0004.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0005.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0006.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0007.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0008.rgstats"))
    (await-task)
    (click (role button :name "Open another capture"))
    (click (role button :name "Capture run-0009.rgstats"))
    (await-task)
    (expect-selected (role tab :name "run-0009.rgstats"))
    ; every tab offers its close button
    (expect-count (button-prefix "Close run-") 10)
    (mark-metrics)
    (click (role tab :name "run-0000.rgstats"))
    (expect-selected (role tab :name "run-0000.rgstats"))
    ; the window, the tabs, the capture, trust, and baseline bars, the
    ; Overview, and the inspector render for the arriving capture; the
    ; view rail is kept. None of it depends on how many tabs are open
    (expect-component-work :rendered 7 :compared 7 :skipped 1 :mounted 0 :retired 0)))
