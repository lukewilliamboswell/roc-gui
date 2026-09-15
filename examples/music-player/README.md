# Music Player

A capability-scoped local music player. Choose a folder, browse its virtualized
track list, and use the playback queue, pause, seek, status, stop, next, and
previous controls. Folder and output authority are explicit; the application
never receives an ambient filesystem path.

The host uses Rodio 0.22.2 and its Symphonia decoder. Normal runs require
`--host-cap-dir PATH --host-cap-audio`. Semantic specifications grant the same
Rodio decoder/player/mixer graph a paced null output sink, so CI needs no audio
device and does not substitute a second player implementation.

`generate_fixture.py` deterministically creates 200 short PCM WAV tracks and
one corrupt file. The generated files are redistributable test tones, and the
ordinary-use scaling case browses the complete library through the production
scanner and mounted virtual list.
