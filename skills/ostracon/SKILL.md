---
name: ostracon
description: Read and manage the user's tasks and projects in Ostracon, their macOS task manager, with the ostracon-cli command. Use when the user asks what's on their list, what's due today or overdue, to add, reschedule, complete or delete a task or subtask, to set a reminder, or to create, rename or remove a project in Ostracon, including "add X to my todo list" or "what do I have on tomorrow" when Ostracon is their task manager.
---

# Ostracon

Ostracon is a Todoist-style task manager for macOS backed by SQLite. `ostracon-cli` reads and changes the same database as the app, whether or not the app is open, and the app shows the changes within a second.

## Finding the command

Use the first of these that exists:

1. `ostracon` or `ostracon-cli` on the `PATH` (`command -v ostracon ostracon-cli`)
2. `/Applications/Ostracon.app/Contents/MacOS/ostracon-cli`
3. `~/Applications/Ostracon.app/Contents/MacOS/ostracon-cli`
4. In a checkout of the Ostracon repository: `build/Ostracon.app/Contents/MacOS/ostracon-cli`, or `swift run ostracon-cli`

If none exists, tell the user Ostracon isn't installed. Releases are at https://github.com/bevan-philip/ostracon/releases. Don't set `OSTRACON_DATABASE` unless the user asks; it points the CLI at a different database from the app's.

`ostracon-cli --help` lists every command and option.

## Reading

```bash
ostracon-cli list                        # open tasks, grouped by project, in outline order
ostracon-cli list --today                # due today or overdue
ostracon-cli list --due-by 'next week'   # due on or before a day
ostracon-cli list -p Home --all          # one project, including completed tasks
ostracon-cli list --search dentist       # name or details contain the text
ostracon-cli show 12                     # one task with details, reminders and every subtask
ostracon-cli projects                    # projects with IDs and open-task counts
```

The filters can be combined. Each line starts with the task's ID, and subtasks are indented under their parent:

```
Home
4  [ ] Move house  due tomorrow 17:00 · 0/2 subtasks
5    [ ] Book van
```

Add `--json` to any command when you need exact fields: `id`, `content`, `project`, `project_id`, `parent_id`, `due` (`2026-11-02` or `2026-11-02T14:00`, local time), `overdue`, `completed`, `reminders`, `details`, `depth`. When you report to the user, describe due dates in words ("tomorrow at 5pm") rather than raw ISO.

## Adding

```bash
ostracon-cli add 'Pay rent tomorrow 9am #Home !1h'
```

As in the app, the text is read for quick-add syntax, and what it finds is taken out of the name:

- `#Project Name` files the task in that project. It must already exist, and multi-word names work.
- A date or time anywhere in the text sets the due date: `today`, `tonight`, `fri`, `next fri`, `next week`, `in 3 days`, `jan 27`, `2027-01-27`, `5pm`, `noon`.
- `!30min`, `!1 hour before` or `!1d` adds a reminder before the due time; `!tomorrow 9am` or `!3pm` adds one at a set time.

Flags do the same thing explicitly and win over the text: `--project/-p`, `--due/-d`, `--remind/-r` (repeatable), `--details`, `--parent ID` (a subtask, which must be in the same project as its parent).

**Always single-quote task text.** Otherwise the shell can treat `#Home` as a comment or try to expand `!1h`.

**Use `--literal` when the name contains words that would be read as dates but aren't meant as the due date.** For example, `ostracon-cli add 'Plan Monday standup'` gives a task called "Plan standup" due Monday. `ostracon-cli add 'Plan Monday standup' --literal` keeps the name as written; add `--due` if it also needs a date. When unsure, check the `Added …` line to see what was read.

A reminder before the due time ("30min") only fires when the task's due date has a time. On an all-day task, or one with no due date, use a set time instead (`!9am`, `--remind 'tomorrow 9am'`). Timed tasks also notify at their due time without any reminder. The Ostracon app delivers the notifications.

## Changing

```bash
ostracon-cli edit 12 --due 'fri 3pm'          # reschedule; the time and date are both replaced
ostracon-cli edit 12 --no-due                 # remove the due date
ostracon-cli edit 12 --remind 30min -r 1d     # replaces all reminders
ostracon-cli edit 12 --no-reminders
ostracon-cli edit 12 --content 'New name'     # taken literally, not re-read for #project or dates
ostracon-cli edit 12 --details 'Notes…'
ostracon-cli edit 12 -p Work                  # moves it and its subtasks to the end of that project
ostracon-cli done 12 13                       # completes tasks and all their subtasks
ostracon-cli reopen 12                        # also reopens completed parents
```

`edit` only changes what you pass. `done` and `reopen` check every ID before changing anything.

Projects are named or given by ID (case doesn't matter):

```bash
ostracon-cli project add 'Work Admin' --color 'lime green'
ostracon-cli project edit 'Work Admin' --name Admin --color teal
```

Colours: berryRed, red, orange, yellow, oliveGreen, limeGreen, green, mintGreen, teal, skyBlue, lightBlue, blue, grape, violet, lavender, magenta, salmon, charcoal, grey, taupe. The Inbox can't be renamed, recoloured or deleted.

## Deleting

Deleting is permanent: `delete` removes a task and all its subtasks, and `project delete` removes a project and every task in it. When the user has finished a task, complete it with `done` instead. Don't delete anything the user didn't clearly ask you to delete. If a deletion would also remove subtasks or tasks they didn't mention, tell them how many and confirm first.

The CLI can't prompt from an agent's shell, so pass `--yes`:

```bash
ostracon-cli delete 12 --yes
ostracon-cli project delete 'Old stuff' --yes
```

## Errors

Errors go to stderr, starting with `ostracon-cli:`. Exit status 64 means the command was mistyped; check `--help`. Exit status 1 means Ostracon refused, such as an unknown task ID, a project that doesn't exist, or a date it couldn't read. Read the message and fix the arguments instead of retrying unchanged. Words such as "yesterday" aren't understood, so use a calendar date. To find a task's ID, run `list --search` or `list --json` first. Never guess an ID.
