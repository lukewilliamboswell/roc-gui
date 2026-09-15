# Terminal Workspace

A cross-platform terminal workspace with real pseudo-terminal sessions, tabs,
split panes, scrollback, search, and reusable layouts.

## Core capabilities

- Production PTY lifecycle, terminal parsing, cell rendering, resize propagation, and child exit handling.
- Tabs and nested splits with keyboard navigation, zoomed panes, titles, and activity indicators.
- Scrollback virtualization, selection, copy/paste, URL recognition, and incremental search.
- Configurable fonts, colors, key bindings, shell profiles, tasks, and restored layouts.
- Correct text input including composed characters, wide glyphs, combining marks, and IME interaction.

## Happy paths

- Start a shell, run a deterministic command, select and copy output, search scrollback, and clear the terminal.
- Create tabs and splits, move focus by keyboard, resize panes, and close an exited session.
- Save a workspace layout and restore its structure with fresh sessions on the next launch.
- Change a theme or font and see every live terminal update without losing terminal state.

## Error paths

- Spawn failures, missing shells, denied working directories, invalid encodings, and unexpected child exits are actionable.
- Paste of multiline or control-bearing text is confirmed according to policy and never silently executed.
- Closing live sessions distinguishes pane, tab, and window scope and supports cancellation.
- A renderer slowdown may defer presentation but cannot lose or reorder PTY bytes.

## High-level goals

- Stress high-rate incremental rendering and the complete keyboard/text-input path.
- Establish reusable process lifecycle, split-layout, command, and preference patterns.
- SCM specs exercise a deterministic child program through the real PTY and cover input, output, search, layout, and exit.
- A scaling case produces long, varied scrollback through an ordinary terminal command.
