(test "Textarea: append to 10000 bytes with unmemoized editor"
  (benchmark :warmups 2 :samples 7 :iterations 1
             :scale 10001 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Use unmemoized editor"))
    (click (role button :name "Load 10000 bytes"))
    (expect-value-bytes (role textarea :name "Large request body") 10000)
    (mark-metrics)
    (click (role button :name "Append byte"))
    (expect-patch :kind replace :staged 5 :removed 5)
    (expect-component-work :rendered 1 :compared 0 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-value-bytes (role textarea :name "Large request body") 10001)))
