(test "record the HTTP workbench gallery journey"
  (grants
    (http-origin "http://127.0.0.1:38191")
    (server "fixture_server.py" 38191))
  (steps
    (settle)
    (screenshot "request")
    (focus (role textbox :name "Request URL"))
    (key "ctrl-a")
    (type "http://127.0.0.1:38191/echo")
    (focus (role textarea :name "Request body"))
    (key "ctrl-a")
    (type "hello from Roc")
    (settle)
    (screenshot "composed")
    (click (role button :name "Send request"))
    (await-task)
    (settle)
    (screenshot "response")))
