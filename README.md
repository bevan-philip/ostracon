# Ostracon

A small SwiftUI task manager for macOS with a Todoist-style workflow and a standard Mac interface, backed by SQLite.

- **Inbox** plus your own colour-coded **projects**
- **`#Project`** anywhere in a task's name files it into that project (multi-word names work, e.g. `#Work Admin`), with autocomplete
- **Nested tasks**: indent, outdent, collapse
- **Keyboard first**: Return saves a task and leaves the composer open for the next one

## Build and run

Requires macOS 15+ and Swift 6 (the Command Line Tools are enough).

```bash
scripts/build-app.sh --open   # builds build/Ostracon.app and launches it
swift test                    # runs the test suite
```

Data lives in `~/Library/Application Support/Ostracon/ostracon.sqlite`. Set `OSTRACON_DATABASE=/some/path.sqlite` to use a different file.

To work in Xcode, open `Package.swift`.

## Keyboard

| Where | Key | Action |
| --- | --- | --- |
| Anywhere | ⌘N / A / Q | Add task to the current project |
| | ⌥⌘N / ⇧A | Add subtask to the selected task |
| | ⇧⌘N | New project |
| | ⌘1 … ⌘9 | Go to Inbox / projects |
| | ⇧⌘C | Show or hide completed tasks |
| Task list | ↑ ↓ or J K | Move selection |
| | ← → | Collapse or expand (← on a leaf jumps to its parent) |
| | Space or ⌘Return | Complete / reopen |
| | Return or ⌘E | Edit |
| | Tab / ⇧Tab (or ⌘] / ⌘[) | Indent / outdent |
| | ⌥⌘↑ / ⌥⌘↓ | Move up / down |
| | Delete | Delete (asks first) |
| | ⌘Z | Undo the last completion (while its toast is showing) |
| Composer | Return | Save; when adding, start the next task straight away |
| | `#` | Project autocomplete: ↑ ↓ to choose, Tab or Return to accept, Esc to dismiss |
| | Esc | Close the composer |

## Layout

```
Sources/OstraconCore   SQLite wrapper, repository, #-parser, task tree (no UI)
Sources/Ostracon       SwiftUI app, organised by feature (Sidebar, TaskList, Composer, Toast)
Tests/                 Swift Testing suites for the core and the app model
scripts/               App bundling and icon generation
```
