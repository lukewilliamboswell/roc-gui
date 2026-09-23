;; A failing step is read where it happened (US-20). The Counter's counting
;; specification, edited to expect one render more than the Counter does,
;; fails at its component work assertion on line 7: the line is marked, the
;; diagnostic is beneath it, and the assertion's expected and observed values
;; are a table with the mismatch marked. The steps after it never ran, so their
;; lines carry nothing.
(test "a failing step shows its diagnostic and assertion on its line"
  (grants
    (file "fixture/failing/counter-regressed.rgstats")
    (directory "fixture/sources"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (click (role button :name "Open spec sources"))
    (await-task)
    ; browse, then counter-regressed, which matches
    (expect-hash-counters 2 0 1842)
    (expect-visible (within (role row :name "Source bar") (text "counter-regressed.scm")))
    (expect-visible (within (role row :name "Source line 6") (text "✓")))
    (expect-visible (within (role row :name "Source line 7") (text "✗")))
    (expect-visible (within (role row :name "Hint line 7") (text-prefix "┆ ")))
    (expect-visible (role row :name "Assertions line 7"))
    (expect-visible (within (role row :name "Assertion component work rendered line 7") (text "✗")))
    (expect-visible (within (role row :name "Assertion component work rendered line 7") (text "2")))
    (expect-visible (within (role row :name "Assertion component work rendered line 7") (text "1")))
    (expect-not-visible (within (role row :name "Assertion component work compared line 7") (text "✗")))
    (expect-not-visible (within (role row :name "Source line 8") (text "✓")))
    (expect-not-visible (within (role row :name "Source line 8") (text "✗")))
    (click (role button :name "Line 7"))
    (expect-visible (within (role scroll :name "Step inspector") (role column :name "Step diagnostic")))
    (expect-visible (within (role scroll :name "Step inspector") (text "fail · —")))))
