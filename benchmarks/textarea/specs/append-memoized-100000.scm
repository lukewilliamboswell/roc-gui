(test "Textarea: append to 100000 bytes with memoized editor"
  (benchmark :warmups 2 :samples 7 :iterations 1
             :scale 100001 :initial-size 100000 :change-size 1)
  (steps
    (click (role button :name "Use memoized editor"))
    (click (role button :name "Load 100000 bytes"))
    (expect-value-bytes (role textarea :name "Large request body") 100000)
    (mark-metrics)
    (click (role button :name "Append byte"))
    (expect-patch :kind replace :staged 5 :removed 5)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)
    (expect-value-bytes (role textarea :name "Large request body") 100001)))
