(test "navigate nested folders, select entries, and preserve history"
  (grants
    (directory "fixture"))
  (steps
    (expect-file-picks 0) (expect-file-lists 0) (expect-file-opens 0) (expect-file-reads 0)
    (expect-file-selection-counters 0 0 0 0 0 0 1)
    (click (role button :name "Open project"))
    (await-task)
    (expect-file-picks 1) (expect-file-lists 1) (expect-file-opens 0) (expect-file-reads 0)
    (click (role button :name "Select Folder: nested"))
    (expect-visible (text "Selected: nested"))
    (click (role button :name "Open folder nested"))
    (await-task)
    ; the path is a strip of segments now, not one joined string
    (expect-visible (text "nested"))
    (expect-visible (text "›"))
    (expect-file-picks 1) (expect-file-lists 2) (expect-file-opens 1) (expect-file-reads 0)
    (click (role button :name "Select File: item.txt"))
    (expect-visible (text "Selected: item.txt"))
    (click (role button :name "Back"))
    (expect-visible (role button :name "Open folder nested"))
    (click (role button :name "Forward"))
    ; the path is a strip of segments now, not one joined string
    (expect-visible (text "nested"))
    (expect-visible (text "›"))
    (click (role button :name "Breadcrumb root"))
    (expect-visible (role button :name "Open folder nested"))
    (expect-file-picks 1) (expect-file-lists 2) (expect-file-opens 1) (expect-file-reads 0)))
