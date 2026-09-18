(test "Textarea: same-length late edit of 10000 bytes with memoized editor"
  (benchmark :warmups 2 :samples 7 :iterations 1
             :scale 10000 :initial-size 10000 :change-size 1)
  (steps
    (click (role button :name "Use memoized editor"))
    (click (role button :name "Load 10000 bytes"))
    (mark-metrics)
    (click (role button :name "Edit last byte"))
    (expect-value-bytes (role textarea :name "Large request body") 10000)
    (expect-patch :kind replace :staged 5 :removed 5)
    (expect-component-work :rendered 1 :compared 1 :skipped 0 :mounted 0 :retired 0 :registry-visits 1)))
