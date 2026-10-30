# Ostracon

A small SwiftUI task manager for macOS with a Todoist-style workflow and a standard Mac interface, backed by SQLite.

- **Inbox** plus your own colour-coded **projects**
- **`#Project`** anywhere in a task's name files it into that project (multi-word names work, e.g. `#Work Admin`), with autocomplete
- **Due dates** typed Todoist-style anywhere in a task's name — `tomorrow 5pm`, `next fri`, `in 3 days`, `jan 27`, `27/1`, `end of month` — or picked from the date chip
- **Reminders** with `!`: `!30min` before the due time, or `!tomorrow 9am`; timed tasks also notify at their due time
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
| | Backspace after a block | Turn the block back into text |
| | Esc | Close the composer |

## Dates and reminders

Type a date anywhere in the task name and, once you type the space after it, it becomes a block (projects and `!reminders` too); the date chip shows what it means. **Backspace over a block** to turn it back into plain words that stay plain, so a task can still be called "Plan Monday's standup". An existing task's name is never re-read when you edit it.

| Type | Means |
| --- | --- |
| `today`, `tomorrow` (`tmrw`), `tonight` | That day (tonight is 7pm) |
| `friday`, `fri`, `this friday`, `next friday` | The coming Friday, this week's, or next week's |
| `next week`, `weekend`, `next weekend`, `next month`, `end of month` | Monday, Saturday, the 1st, the last day |
| `in 3 days`, `in 2 weeks`, `in a month`, `in 2 hours` | Relative to now |
| `jan 27`, `27th january 2027`, `27/1`, `2027-01-27` | A calendar date (numeric order follows your region) |
| `at 5pm`, `5:30pm`, `17:00`, `at 17`, `noon` | A time, alone or with any date above |
| `!30min`, `!1 hour before`, `!1d` | A reminder before the due time |
| `!tomorrow 9am`, `!3pm` | A reminder at a set time (a bare time is on the due day) |

Notifications need permission the first time they're scheduled; they only work from the built `.app`, not `swift run`.

## Layout

```
Sources/OstraconCore   SQLite wrapper, repository, #-and-date parsers, task tree, reminder schedule (no UI)
Sources/Ostracon       SwiftUI app, organised by feature (Sidebar, TaskList, Composer, Reminders, Toast)
Tests/                 Swift Testing suites for the core and the app model
scripts/               App bundling and icon generation
```
