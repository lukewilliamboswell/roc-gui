(test "Semantic ancestor scopes cross transparent component markers"
  (steps
    (expect-visible (within (role column :name "Review board") (text "Draft 0")))
    (click (within (role column :name "Review board") (role button :name "Edit draft")))
    (expect-visible (within (role column :name "Review item") (text "Draft 1")))
    (click (role button :name "Refresh queue"))
    (click (within (role column :name "Review board") (role button :name "Edit draft")))
    (expect-visible (within (role column :name "Review item") (text "Draft 2")))))
