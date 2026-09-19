; The same registry answering for a resource shaped nothing like a directory.
;
; A device grant may open a connection and derive one; the connection it derives
; may read and write. Neither right set contains the other, although the second
; is plainly derived from the first, which is why derivation is about scope and
; not about a rights lattice. The connection is still bound to the grant: it
; carries the same origin, so a connection can never claim to have been chosen
; by a person when the device behind it was named by a command-line flag.
(test "a device grant and the connection it derives are both readable authority"
  (grants
    (device virtual))
  (steps
    (expect-grants)
    (click (role button :name "Discover devices"))
    (await-task)
    ; Discovery acquires the grant and releases it again: it asked what was
    ; there, it did not open anything. Releasing is not revoking, and the
    ; counters say which happened.
    (expect-grants)
    (expect-grant-counters 1 1 0 0)
    (click (role button :name "Connect device"))
    (await-task)
    (expect-device-connections 1)
    (expect-grants
      "device provisioned/consent-only derived read,write")
    (expect-grant-counters 3 2 0 0)
    (click (role button :name "Disconnect device"))
    (await-task)
    (expect-device-connections 0)
    (expect-grants)
    (expect-grant-counters 3 3 0 0)))
