# Example applications

These directories define the application examples used to demonstrate Roc GUI
and to drive platform development. An example is intended to become a useful,
realistic application rather than a component demo, test fixture, or synthetic
benchmark.

Each application README records its product boundary, principal user journeys,
failure behaviour, and the platform capabilities it is expected to exercise.
Implementations and SCM behaviour specifications belong in the same directory.

| Example | Product shape | Primary platform pressure |
| --- | --- | --- |
| [HTTP Workbench](http-workbench/) | HTTP client | asynchronous work and large structured text |
| [Database Browser](database-browser/) | relational database client | data grids and transactional work |
| [File Explorer](file-explorer/) | desktop file manager | filesystem integration and navigation |
| [Terminal Workspace](terminal-workspace/) | terminal emulator | high-rate text and keyboard input |
| [Image Library](image-library/) | image browser and viewer | media loading and direct manipulation |
| [Music Player](music-player/) | local music library | background playback and persistent media state |
| [Clipboard History](clipboard-history/) | clipboard manager | global activation and privacy-sensitive history |
| [System Monitor](system-monitor/) | resource dashboard | continuously changing data and charts |
| [Settings Center](settings-center/) | system control surface | forms, validation, and apply/revert workflows |
| [Device Configurator](device-configurator/) | peripheral configuration tool | device lifecycle and transactional changes |
| [Animation Studio](animation-studio/) | timeline-based graphics editor | canvas interaction, timelines, and undo |
| [Redis Explorer](redis-explorer/) | Redis client | heterogeneous data and live server state |

Every completed example has deterministic first-run data, semantic locators,
SCM specifications for its meaningful behaviour, and a scaling case reached
through normal application use. External services and hardware may have a
local deterministic counterpart, but verification uses the same application
graph and event route as interactive use.
