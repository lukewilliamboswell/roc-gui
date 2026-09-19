; The trusted App access surface, opened the way a person opens it.
;
; This is the claim in the resource access guide that nothing could reach:
; "a person can withdraw a grant". Revocation was implemented, specified, and
; unreachable — grant::revoke was callable from a test step and from nothing
; anyone could press. A model whose most reassuring sentence has no control
; behind it is a model nobody has reason to believe.
;
; The chord belongs to the host, bound beside Tab and Escape, and the surface it
; opens is drawn by the host as a sibling of the application's root. That is why
; nothing below names it with a locator: it has no node, no identity, and no
; place in the graph an application could find, style, or notice. `expect-app-access`
; exists because of that, and because the first version of this case passed while
; the surface never drew — every claim in it was about the application and true
; either way.
(test "a person can see what this application holds"
  (grants
    (directory "fixture"))
  (steps
    (settle)
    (expect-app-access closed)
    (click (role button :name "Open project"))
    (await-task)
    (settle)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive")
    ; Opened through the production keymap, with nothing in the application
    ; focused first: a host chord must not depend on where an application
    ; happens to have put focus.
    (key "secondary-shift-a")
    (settle)
    (expect-app-access open)
    (screenshot "app-access")
    ; The application is untouched underneath. Its graph does not gain a node,
    ; lose one, or learn that the surface is there.
    (expect-visible (role row :name "Directory toolbar"))
    (expect-grants
      "directory provisioned/consent-only root read,list,derive")
    ; And the same chord closes it, leaving the window as it was.
    (key "secondary-shift-a")
    (settle)
    (expect-app-access closed)
    (expect-on-screen (role row :name "Directory toolbar"))))
