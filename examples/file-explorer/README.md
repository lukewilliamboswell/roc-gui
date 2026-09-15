# File Explorer

A practical desktop file manager for navigating and organizing user-selected
directories. Access begins with an explicit directory grant and respects platform
permission boundaries.

## Core capabilities

- Breadcrumb, tree, list, and grid navigation with history, tabs, and optional split views.
- Stable multi-selection, keyboard range selection, sorting, filtering, and hidden-file policy.
- Create, rename, copy, move, duplicate, trash, and restore workflows with progress and cancellation.
- Drag-and-drop, clipboard file operations, previews, metadata, and operating-system open/reveal actions.
- Incremental directory loading and virtualization for large folders.

## Happy paths

- Grant a directory, traverse nested folders, use Back/Forward, and return through breadcrumbs.
- Select multiple entries, copy or move them, resolve a name collision, and undo where supported.
- Create and rename a folder, filter the current view, and open a file with its registered application.
- Reopen the application and restore granted roots and navigation state as platform policy allows.

## Error paths

- Cancellation, denied access, revoked grants, missing entries, read-only destinations, and full disks are explicit states.
- Partial batch operations report exactly which entries completed and which remain recoverable.
- Symlink cycles and filesystem changes during enumeration do not corrupt navigation or selection.
- Destructive operations identify exact targets and never follow unresolved or unexpectedly changed paths.

## High-level goals

- Extend the existing folder-browser capability into a complete application without creating a second filesystem route.
- Drive platform dialogs, grants, drag-and-drop, menus, large lists, icons, and file watching.
- SCM specs use a repository-owned fixture and cover navigation, selection, mutation, conflicts, cancellation, and recovery.
- A scaling case opens a naturally populated directory through the production enumeration and rendering path.
