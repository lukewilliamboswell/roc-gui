; The boundaries of the trail. At the root there is nothing behind you, so no
; Back and no ancestor chip exist. Two levels down, one press on the first chip
; has to drop the whole tail rather than one level of it.
(test "Breadcrumbs collapse a deep trail and the root offers no way back"
  (grants
    (directory "fixture"))
  (steps
    (click (role button :name "Choose directory"))
    (await-task)
    (expect-visible (text "alpha.txt"))
    (expect-not-visible (role button :name "Back"))
    (expect-not-visible (role button :name "Breadcrumb 0"))
    (click (role button :name "Open directory many"))
    (await-task)
    (expect-visible (role button :name "Back"))
    (expect-visible (role button :name "Breadcrumb 0"))
    (expect-not-visible (role button :name "Breadcrumb 1"))
    (click (role button :name "Open directory zzz-folder"))
    (await-task)
    (expect-visible (text "keep.txt"))
    (expect-visible (role button :name "Breadcrumb 1"))
    (expect-not-visible (role button :name "Breadcrumb 2"))
    ; one press on the first chip returns to the root, not to "many"
    (click (role button :name "Breadcrumb 0"))
    (await-task)
    (expect-visible (text "alpha.txt"))
    (expect-visible (role button :name "Open directory many"))
    (expect-not-visible (role button :name "Back"))
    (expect-not-visible (role button :name "Breadcrumb 0"))))
