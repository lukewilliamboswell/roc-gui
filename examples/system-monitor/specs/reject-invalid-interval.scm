(test "reject invalid timer interval without allocating a subscription"
  (steps
    (expect-subscriptions 0)
    (click (role button :name "Validate timer bounds"))
    (expect-visible (text "Invalid interval rejected"))
    (expect-subscriptions 0)))
