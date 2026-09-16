# The demonstration library

The four recordings here are the library the music player is meant to be seen
with. They are real performances of public-domain piano music, not test tones,
because a player whose queue sounds like a signal generator demonstrates the
audio pipeline and nothing else.

Every recording is published on Wikimedia Commons under the Creative Commons
CC0 1.0 Universal Public Domain Dedication. Each file below was identified by
the SHA-1 of the original download, so the licence statement quoted is the one
on that exact file page, and each page's `LicenseShortName` reads `CC0` with
`AttributionRequired` false.

| File | Source | Licence |
| --- | --- | --- |
| `Chopin - Nocturne in B-flat minor, Op. 9 No. 1.wav` | <https://commons.wikimedia.org/wiki/File:NocturneOp.9No.1InBFlatMinor.mp3> | CC0 1.0 (<http://creativecommons.org/publicdomain/zero/1.0/deed.en>) |
| `Chopin - Polonaise in E-flat minor, Op. 26 No. 2.wav` | <https://commons.wikimedia.org/wiki/File:Chopin_-_Polonaise-op-26-no-2.ogg> | CC0 1.0 |
| `Chopin - Waltz in F major, Op. 34 No. 3.wav` | <https://commons.wikimedia.org/wiki/File:Chopin_-_Waltz_op._34_no_3.ogg> | CC0 1.0 |
| `Schubert - Impromptu in C major, D. 946 No. 3.wav` | <https://commons.wikimedia.org/wiki/File:Franz_Schubert,_Impromptu_Opus_post._D_946_-_No._3_in_C_major_(Allegro).ogg> | CC0 1.0 |

## What was changed

The host builds Rodio with the `wav` feature only, so none of the original
encodings can be played as downloaded, and a full movement of lossless audio
has no business living in a repository forever. Each file is therefore a ten
second excerpt, transcoded with ffmpeg:

```sh
ffmpeg -ss <offset> -t 10 -i <download> \
    -af "afade=t=in:st=0:d=0.5,afade=t=out:st=9.5:d=0.5,loudnorm=I=-18:TP=-2:LRA=11" \
    -ac 1 -ar 22050 -c:a pcm_s16le -map_metadata -1 "<name>.wav"
```

The offsets are 8 s (nocturne), 20 s (polonaise), 12 s (waltz) and 16 s
(impromptu), chosen to start on a phrase rather than on the opening silence.
The half-second fades keep an excerpt from starting and ending on a click, the
loudness normalisation keeps the four at one level, and `-map_metadata -1`
drops the encoder tags so the bytes are only audio. Mono at 22.05 kHz is
430 KiB per excerpt, which is the least that still sounds like a piano.

The file names are the display titles: the player shows a row's name with the
extension removed, so the queue reads as music rather than as a directory
listing.

## The damaged recording

`Unknown - damaged recording.wav` is not audio and never was: it is one line of
text with a `.wav` extension. It is here because a media application that has
never been seen failing a file is not evidence of anything, and the failure is
worth photographing. Its name sorts after every real recording on purpose —
pressing Play on a library nobody has touched must reach music, not the one
file that cannot be decoded. It is our own file and carries no third-party
licence.
