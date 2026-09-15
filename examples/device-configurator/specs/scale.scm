(test "large configurable device uses the ordinary controls view"
  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 12 :change-size 88)
  (steps
    (click (role button :name "Discover devices"))
    (await-task)
    (click (role button :name "Connect device"))
    (await-task)
	(mark-metrics)
	(click (role button :name "Select profile 5"))
    (expect-count (text-prefix "Control ") 100)
    (expect-visible (text "Control 100: Primary action"))
    (expect-device-connections 1)))
