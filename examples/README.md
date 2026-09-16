# Example applications

These directories define the application examples used to demonstrate Roc GUI
and to drive platform development. An example is intended to become a useful,
realistic application rather than a component demo, test fixture, or synthetic
benchmark.

Each application README says what the application is, what platform capability it
exercises, how to run it including any grant it needs, and what it does not do
yet. Implementations and SCM behaviour specifications belong in the same
directory.

| Example | Product shape | Primary platform pressure |
| --- | --- | --- |
| [HTTP Workbench](http-workbench/) | single-document HTTP client | one-origin authority and asynchronous work |
| [Database Browser](database-browser/) | read-only SQLite browser | data grids and worker-task queries |
| [File Explorer](file-explorer/) | read-only file manager | filesystem authority and navigation |
| [Folder browser](folder-browser/) | single-folder reader | the directory grant on its own |
| [Counter](counter/) | two independent tallies | state boundaries and component embedding |
| [Terminal Workspace](terminal-workspace/) | one terminal pane | process authority and high-rate text |
| [Image Library](image-library/) | image browser and viewer | media loading and image rendering |
| [Music Player](music-player/) | local music library | audio output over long-running tasks |
| [Clipboard History](clipboard-history/) | clipboard manager | explicit text authority and bounded capture |
| [System Monitor](system-monitor/) | resource dashboard | continuous sampling and charts |
| [Settings Center](settings-center/) | preferences window | controlled inputs and durable storage |
| [Device Configurator](device-configurator/) | peripheral configuration tool | device lifecycle and transactional changes |
| [Animation Studio](animation-studio/) | timeline-based graphics editor | canvas interaction, timelines, and undo |
| [Redis Explorer](redis-explorer/) | read-only Redis client | a capability-owned TCP stream |

Every completed example has deterministic first-run data, semantic locators,
SCM specifications for its meaningful behaviour, and a scaling case reached
through normal application use. External services and hardware may have a
local deterministic counterpart, but verification uses the same application
graph and event route as interactive use.
