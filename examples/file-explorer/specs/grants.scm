; What authority this application is holding, read back from the one registry
; that answers for every resource. Counting grants would not do: a count passes
; for an application holding entirely different authority than the one named
; here, and the whole point of a grant is which resource it is over and how it
; arrived.
;
; `--host-cap-dir` is development provisioning, so every grant below says
; `provisioned` and not `trusted-selection`. That distinction is the one
; docs/resource-access.adoc requires never be blurred, and this is where a
; regression in it would be caught.
(test "the authority an application holds can be read back"
  (grants
    (directory "fixture"))
  (steps
    ; Before anything is asked for, the application holds nothing at all.
    (expect-grants)
    (expect-grant-counters 0 0 0 0)
    (click (role button :name "Open project"))
    (await-task)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive")
    ; Opening a child derives a second grant beneath the first. It is read-only
    ; and it can derive again, because that is what a directory grant is; it is
    ; not a wider authority than the root it came from.
    (click (role button :name "Open folder nested"))
    (await-task)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive"
      "directory provisioned/consent-only derived read,list,derive")
    ; Revocation reaches the derived grant as well as the root, and both say so
    ; wherever they are read rather than simply disappearing.
    (revoke-file-grants)
    (expect-grants
      "directory provisioned/consent-only root read,list,derive revoked"
      "directory provisioned/consent-only derived read,list,derive revoked")
    (expect-grant-counters 2 0 2 0)))
