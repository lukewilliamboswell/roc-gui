; Reading is the one operation whose success is invisible unless the
; application shows it. A Read control that leaves the window exactly as it
; found it cannot be told apart from a Read control that does nothing, so the
; result is evidence: the size the grant returned, and the file's own first
; line.
(test "reading a file through the grant produces visible evidence"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Open project"))
    (await-task)
    (expect-file-reads 0)
    (click (role button :name "Select File: alpha.txt"))
    (expect-visible (text "Selected: alpha.txt"))
    ; nothing has been read yet, so nothing claims to have been
    (expect-not-visible (text "Read 6 bytes"))
    (click (role button :name "Read file alpha.txt"))
    (await-task)
    (expect-file-reads 1)
    (expect-visible (text "Read 6 bytes"))
    (expect-visible (text "alpha"))
    ; the evidence belongs to the entry it came from: selecting another entry
    ; must not leave the previous file's result standing under a new name
    (click (role button :name "Select File: beta.txt"))
    (expect-visible (text "Selected: beta.txt"))
    (expect-not-visible (text "Read 6 bytes"))
    (expect-file-reads 1)
    ; and reading again reaches the grant again rather than reusing an answer
    (click (role button :name "Read file beta.txt"))
    (await-task)
    (expect-file-reads 2)
    (expect-visible (text "Read 5 bytes"))))
