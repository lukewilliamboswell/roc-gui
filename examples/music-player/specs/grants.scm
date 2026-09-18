; Three kinds of authority held at once, and the lineage between two of them.
;
; A track is derived from the audio output it plays through, so it carries the
; output's origin and dies with it: a track can never outlive the device that
; opened it. The music folder is a separate root that the track does not descend
; from, although the bytes came from there — the decoder read them once, and the
; contract says plainly that bytes already given to an application are not
; recalled by revoking where they came from.
;
; The rights differ between parent and child and neither contains the other. An
; output may connect and derive; the track it derives may read and write. That
; is ordinary, and a model that insisted a child's rights be a subset of its
; parent's could not express it.
(test "an application holding three kinds of authority can say what they are"
  (grants
    (directory "library")
    (audio null))
  (steps
    (expect-grants)
    (click (role button :name "Choose music folder"))
    (await-task)
    (expect-visible (text "5 tracks"))
    ; The output is acquired with the folder, before any track is chosen: the
    ; device is opened once and every track plays through it.
    (expect-grants
      "audio provisioned/consent-only root derive,connect"
      "directory provisioned/consent-only root read,list,derive")
    (click (role button :name "Play Chopin - Nocturne in B-flat minor, Op. 9 No. 1"))
    (await-task)
    (expect-visible (text "Playing"))
    (expect-grants
      "audio provisioned/consent-only root derive,connect"
      "audio provisioned/consent-only derived read,write"
      "directory provisioned/consent-only root read,list,derive")))
