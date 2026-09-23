;; Granting a folder of specification sources shows the one the capture ran
;; (US-19). The capture names it only by spec_name and spec_hash, so the host
;; hashes the folder's .scm files in name order until one matches: browse,
;; counter-regressed, counting, independence, and then scale-100, 3,875 bytes
;; in all. Every step of this benchmark is on line 5, so that line's gutter
;; holds all nine; the sample runs give a median, and the inspector lists each
;; sample's own values beside it (US-21).
(test "a granted folder of sources annotates the specification a capture ran"
  (grants
    (file "fixture/captures/database-browser-scale-100.rgstats")
    (directory "fixture/sources"))
  (steps
    (click (role button :name "Open capture"))
    (await-task)
    (click (role button :name "Spec"))
    (expect-visible (text "Grant the folder of specification sources to see the steps on their lines."))
    (expect-visible (role virtual-list :name "Steps"))
    (expect-hash-counters 0 0 0)
    (click (role button :name "Open spec sources"))
    (await-task)
    (expect-hash-counters 5 0 3875)
    (expect-visible (within (role row :name "Source bar") (text "scale-100.scm")))
    (expect-visible (within (role row :name "Source bar") (text "✓ matches spec_hash")))
    (expect-not-visible (role virtual-list :name "Steps"))
    (expect-rows (role virtual-list :name "Source") :count 5 :first 0 :mounted 5)
    ; a highlighted line is one text element, located by its whole text
    (expect-visible (within (role row :name "Source line 4") (text "  (benchmark :warmups 1 :samples 3 :iterations 1 :scale 100 :initial-size 0 :change-size 100)")))
    (expect-visible (within (role row :name "Source line 1") (text "(test \"browse 100 database rows\"")))
    ; only the line the steps ran from carries a result
    (expect-visible (within (role row :name "Source line 5") (text "✓")))
    (expect-not-visible (within (role row :name "Source line 4") (text "✓")))
    ; a summary capture keeps no cycles from before the benchmark's mark, so
    ; the line's total is a dash; the inspector has the measured steps' cycles
    (expect-visible (within (role row :name "Source line 5") (role button :name "Why host_cycles")))
    (click (role button :name "Line 5"))
    (expect-visible (within (role scroll :name "Step inspector") (text "LINE 5 · 9 steps")))
    (expect-count (within (role scroll :name "Step inspector") (role column :name "Step kind")) 9)
    (expect-count (within (role scroll :name "Step inspector") (text-prefix "cycles —: ")) 5)
    (expect-visible (within (role scroll :name "Step inspector") (text "1 cycle · replace")))
    (expect-not-visible (within (role scroll :name "Step inspector") (text "SAMPLES · median shown")))
    ; the median across the three samples, with each sample beside it
    (click (role button :name "Run median"))
    (await-task)
    (click (role button :name "Line 5"))
    (expect-count (within (role scroll :name "Step inspector") (text "SAMPLES · median shown")) 9)
    (expect-count (within (role scroll :name "Step inspector") (role column :name "Sample 0")) 9)
    (expect-count (within (role scroll :name "Step inspector") (role column :name "Sample 2")) 9)
    ; choosing a run shows that run again, and hashes nothing
    (click (role button :name "Run 1"))
    (await-task)
    (expect-hash-counters 5 0 3875)
    (click (role button :name "Line 5"))
    (expect-not-visible (within (role scroll :name "Step inspector") (text "SAMPLES · median shown")))))
