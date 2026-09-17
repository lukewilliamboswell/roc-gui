(test "A rejecting setter discards updates, delegation, and task launch"
 (steps
  (click (role button :name "Lock draft"))
  (click (role button :name "Edit draft"))
  (expect-visible (text "Draft 0"))
  (expect-component-work :rendered 0 :compared 0)
  (click (role button :name "Archive draft"))
  (expect-visible (text "Draft 0"))
  (expect-component-work :rendered 0 :compared 0)
  (click (role button :name "Enrich draft"))
  (expect-component-work :rendered 0 :compared 0)
  (click (role button :name "Unlock draft"))
  (click (role button :name "Edit draft"))
  (expect-visible (text "Draft 1"))))
