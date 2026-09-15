(test "report unsupported Redis value types"
  (steps
    (click (role button :name "Connect to Redis"))
    (await-task)
    (replace-text (role textbox :name "Key pattern") "unsupported:*")
    (click (role button :name "Refresh Redis keys"))
    (await-task)
    (click (role button :name "Inspect Redis key unsupported:events"))
    (await-task)
    (expect-visible (role panel :name "Redis error"))
    (expect-visible (text "This Redis value type is not supported"))))
