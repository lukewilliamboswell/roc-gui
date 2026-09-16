(test "Textarea: append to 1000 bytes with unmemoized editor"
  (benchmark :warmups 2 :samples 7 :iterations 1
             :scale 1001 :initial-size 1000 :change-size 1)
  (steps
    (click (role button :name "Use unmemoized editor"))
    (click (role button :name "Load 1000 bytes"))
    (expect-value-bytes (role textarea :name "Large request body") 1000)
    (mark-metrics)
    (click (role button :name "Append byte"))
    (expect-patch :kind replace :staged 4 :removed 4)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-value-bytes (role textarea :name "Large request body") 1001)))
