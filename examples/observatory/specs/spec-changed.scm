;; A specification edited after its capture no longer hashes to spec_hash
;; (US-19). The file that declares the capture's test is named, a banner says
;; the specification changed, and no result is placed on its lines: the steps
;; stay listed by the line they ran from. Only the folder's one .scm file is
;; hashed; the notes beside it are not a specification.
(test "a changed specification is named and its lines carry no results"
  (grants
    (file "fixture/captures/counter-counting.rgstats")
    (directory "fixture/sources-edited"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (click (role button :name "Open spec sources"))
    (await-task)
    (expect-hash-counters 1 0 568)
    (expect-visible (within (role row :name "Source bar") (text "counting.scm")))
    (expect-visible (within (role row :name "Source bar") (text "✗ hash differs from spec_hash")))
    (expect-visible (within (role panel :name "Specification changed") (text "Specification changed since capture")))
    (expect-not-visible (role virtual-list :name "Source"))
    (expect-not-visible (role button :name "Run median"))
    (expect-visible (within (role virtual-list :name "Steps") (text "Step line 7")))
    (expect-count (within (role virtual-list :name "Steps") (text-prefix "Step line ")) 10)))
