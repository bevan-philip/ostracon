import Foundation
import OstraconCore

/// The tools Ostracon offers over MCP and the CLI, each a thin layer over `TaskRepository`.
@MainActor
public enum OstraconTools {
    public static func all(repository: TaskRepository, now: @escaping () -> Date = { .now }) -> [MCPTool] {
        let colors = JSONValue.array(ProjectColor.allCases.map { .string($0.rawValue) })
        let dueDescription = """
            Natural language such as "today", "tomorrow 5pm", "next fri", "in 3 days", "jan 27", \
            or ISO "2026-01-27" / "2026-01-27T17:00", in the user's local time.
            """
        let remindersDescription = """
            Reminders, each either before the due time ("30min", "1 hour before", "1d") \
            or at a moment ("tomorrow 9am", "3pm" — a bare time falls on the due day).
            """

        func parser() -> DateParser { DateParser(now: now()) }

        func project(_ id: Int64) throws -> Project {
            guard let project = try repository.projects().first(where: { $0.id == id }) else {
                throw ToolError("No project with ID \(id).")
            }
            return project
        }

        func task(_ id: Int64) throws -> TaskItem {
            guard let task = try repository.task(id: id) else { throw ToolError("No task with ID \(id).") }
            return task
        }

        func dueDate(_ text: String) throws -> DueDate {
            let text = text.trimmingCharacters(in: .whitespaces)
            if text.wholeMatch(of: /\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?/) != nil, let due = DueDate(storageValue: text) {
                return due
            }
            guard let due = parser().dueDate(from: text) else {
                throw ToolError("Couldn't read \"\(text)\" as a date. Try \"tomorrow 5pm\", \"next fri\" or \"2026-01-27\".")
            }
            return due
        }

        func reminders(_ texts: [String], due: DueDate?) throws -> [Reminder] {
            try texts.map { text in
                guard let reminder = parser().reminder(from: text, due: due) else {
                    throw ToolError("Couldn't read \"\(text)\" as a reminder. Try \"30min\" or \"tomorrow 9am\".")
                }
                return reminder
            }
        }

        func color(_ name: String?) throws -> ProjectColor? {
            guard let name else { return nil }
            guard let color = ProjectColor(rawValue: name) else {
                throw ToolError("Unknown colour \"\(name)\". Use one of: \(ProjectColor.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            return color
        }

        func describe(_ task: TaskItem) throws -> JSONValue {
            try TaskFormatter(repository: repository, now: now()).task(task)
        }

        return [
            MCPTool(
                name: "list_projects",
                title: "List projects",
                description: "Lists every project, Inbox first, with its ID, colour and number of open tasks.",
                readOnly: true
            ) { _ in
                let tasks = try repository.tasks()
                return ["projects": .array(try repository.projects().map { project in
                    [
                        "id": .number(Double(project.id)),
                        "name": .string(project.name),
                        "color": .string(project.color.rawValue),
                        "is_inbox": .bool(project.isInbox),
                        "open_tasks": .number(Double(TaskTree.openCount(in: tasks, projectID: project.id)))
                    ]
                })]
            },

            MCPTool(
                name: "list_tasks",
                title: "List tasks",
                description: """
                    Lists tasks in outline order (each subtask follows its parent, with its depth). \
                    Open tasks only unless include_completed is set. Filters combine.
                    """,
                properties: [
                    "project_id": ["type": "integer", "description": "Only this project's tasks."],
                    "search": ["type": "string", "description": "Only tasks whose name or details contain this text."],
                    "due_by": [
                        "type": "string",
                        "description": "Only tasks due on or before this day, e.g. \"today\" for today and overdue, or \"next week\"."
                    ],
                    "include_completed": ["type": "boolean", "description": "Include completed tasks. Defaults to false."]
                ],
                readOnly: true
            ) { arguments in
                let projectID = try arguments.id("project_id")
                if let projectID { _ = try project(projectID) }
                let search = try arguments.string("search")?.trimmingCharacters(in: .whitespaces)
                let dueBy = try arguments.string("due_by").map(dueDate)
                let includeCompleted = try arguments.bool("include_completed") ?? false

                let formatter = try TaskFormatter(repository: repository, now: now())
                let rows = formatter.outline(projectID: projectID, includeCompleted: includeCompleted).filter { row in
                    let task = row.task
                    if let search, !search.isEmpty,
                       !task.content.localizedStandardContains(search), !task.details.localizedStandardContains(search) {
                        return false
                    }
                    if let dueBy {
                        guard let due = task.dueDate, due.startOfDay() <= dueBy.startOfDay() else { return false }
                    }
                    return true
                }
                return [
                    "count": .number(Double(rows.count)),
                    "tasks": .array(rows.map { formatter.task($0.task, depth: $0.depth) })
                ]
            },

            MCPTool(
                name: "get_task",
                title: "Get task",
                description: "Gets one task with all of its subtasks, completed or not.",
                properties: ["id": ["type": "integer", "description": "The task's ID."]],
                required: ["id"],
                readOnly: true
            ) { arguments in
                let task = try task(try arguments.requiredID("id"))
                return try TaskFormatter(repository: repository, now: now()).task(task, includingSubtasks: true)
            },

            MCPTool(
                name: "add_task",
                title: "Add task",
                description: """
                    Adds a task, by default to the Inbox. Like Ostracon's quick add, the content may include \
                    "#Project Name", a due date and "!reminders", e.g. "Pay rent tomorrow 9am #Home !1h"; \
                    these are removed from the name. Explicit arguments win over what the content says.
                    """,
                properties: [
                    "content": ["type": "string", "description": "The task's name."],
                    "details": ["type": "string", "description": "Longer notes shown under the name."],
                    "project_id": ["type": "integer", "description": "The project to add it to. Defaults to the parent's project, or the Inbox."],
                    "parent_id": ["type": "integer", "description": "Makes this a subtask of that task, added after its other subtasks."],
                    "due": ["type": "string", "description": .string(dueDescription)],
                    "reminders": ["type": "array", "items": ["type": "string"], "description": .string(remindersDescription)],
                    "quick_add": [
                        "type": "boolean",
                        "description": "Read #project, dates and !reminders out of the content. Defaults to true; turn off to keep the content exactly as given."
                    ]
                ],
                required: ["content"]
            ) { arguments in
                let content = try arguments.requiredString("content")
                let projects = try repository.projects()
                let parsed = try arguments.bool("quick_add") ?? true
                    ? QuickAddParser.parse(content, projects: projects, dates: parser())
                    : QuickAddResult(content: content, projectID: nil)

                let parent = try arguments.id("parent_id").map(task)
                let projectID = try arguments.id("project_id") ?? parent?.projectID ?? parsed.projectID ?? repository.inbox().id
                _ = try project(projectID)
                if let parent, parent.projectID != projectID {
                    throw ToolError("Task \(parent.id) is in a different project, so it can't be the parent.")
                }

                let due = try arguments.string("due").map(dueDate) ?? parsed.dueDate
                let reminders = try arguments.strings("reminders").map { try reminders($0, due: due) } ?? parsed.reminders
                let added = try repository.addTask(
                    content: parsed.content,
                    details: try arguments.string("details") ?? "",
                    projectID: projectID, parentID: parent?.id, dueDate: due, reminders: reminders
                )
                return try describe(added)
            },

            MCPTool(
                name: "update_task",
                title: "Update task",
                description: """
                    Changes a task. Only the fields given are changed. Pass due as null or "" to remove the due date, \
                    and reminders as [] to remove them. Changing project_id moves the task and its subtasks \
                    to the end of that project's top level.
                    """,
                properties: [
                    "id": ["type": "integer", "description": "The task's ID."],
                    "content": ["type": "string", "description": "The new name, taken literally."],
                    "details": ["type": "string", "description": "The new notes."],
                    "due": ["type": ["string", "null"], "description": .string(dueDescription)],
                    "reminders": ["type": "array", "items": ["type": "string"], "description": .string("Replaces every reminder. " + remindersDescription)],
                    "project_id": ["type": "integer", "description": "Moves the task to this project."]
                ],
                required: ["id"]
            ) { arguments in
                let existing = try task(try arguments.requiredID("id"))
                let content = try arguments.string("content") ?? existing.content
                let details = try arguments.string("details") ?? existing.details
                let projectID = try arguments.id("project_id")
                if let projectID { _ = try project(projectID) }

                var due = existing.dueDate
                if arguments.has("due") {
                    let text = try arguments.string("due") ?? ""
                    due = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : try dueDate(text)
                }
                let newReminders = try arguments.strings("reminders").map { try reminders($0, due: due) }

                try repository.updateTask(id: existing.id, content: content, details: details)
                if due != existing.dueDate { try repository.setDueDate(id: existing.id, due) }
                if let newReminders { try repository.setReminders(id: existing.id, newReminders) }
                if let projectID { try repository.moveTask(id: existing.id, toProject: projectID) }
                return try describe(try task(existing.id))
            },

            MCPTool(
                name: "complete_task",
                title: "Complete task",
                description: """
                    Marks a task done, along with all its subtasks. Pass completed: false to reopen it, \
                    which also reopens any completed parents.
                    """,
                properties: [
                    "id": ["type": "integer", "description": "The task's ID."],
                    "completed": ["type": "boolean", "description": "Defaults to true."]
                ],
                required: ["id"]
            ) { arguments in
                let existing = try task(try arguments.requiredID("id"))
                try repository.setCompleted(id: existing.id, try arguments.bool("completed") ?? true)
                return try describe(try task(existing.id))
            },

            MCPTool(
                name: "delete_task",
                title: "Delete task",
                description: "Permanently deletes a task and all of its subtasks. Prefer complete_task for finished work.",
                properties: ["id": ["type": "integer", "description": "The task's ID."]],
                required: ["id"],
                destructive: true
            ) { arguments in
                let existing = try task(try arguments.requiredID("id"))
                try repository.deleteTask(id: existing.id)
                return ["deleted": .number(Double(existing.id)), "content": .string(existing.content)]
            },

            MCPTool(
                name: "add_project",
                title: "Add project",
                description: "Creates a project at the end of the sidebar.",
                properties: [
                    "name": ["type": "string", "description": "The project's name."],
                    "color": ["type": "string", "enum": colors, "description": "Defaults to charcoal."]
                ],
                required: ["name"]
            ) { arguments in
                let created = try repository.createProject(
                    name: try arguments.requiredString("name"),
                    color: try color(arguments.string("color")) ?? .charcoal
                )
                return ["id": .number(Double(created.id)), "name": .string(created.name), "color": .string(created.color.rawValue)]
            },

            MCPTool(
                name: "update_project",
                title: "Update project",
                description: "Renames or recolours a project. The Inbox can't be changed.",
                properties: [
                    "id": ["type": "integer", "description": "The project's ID."],
                    "name": ["type": "string"],
                    "color": ["type": "string", "enum": colors]
                ],
                required: ["id"]
            ) { arguments in
                let existing = try project(try arguments.requiredID("id"))
                guard !existing.isInbox else { throw ToolError("The Inbox can't be renamed or recoloured.") }
                try repository.updateProject(
                    id: existing.id,
                    name: try arguments.string("name") ?? existing.name,
                    color: try color(arguments.string("color")) ?? existing.color
                )
                let updated = try project(existing.id)
                return ["id": .number(Double(updated.id)), "name": .string(updated.name), "color": .string(updated.color.rawValue)]
            },

            MCPTool(
                name: "delete_project",
                title: "Delete project",
                description: "Permanently deletes a project and every task in it. The Inbox can't be deleted.",
                properties: ["id": ["type": "integer", "description": "The project's ID."]],
                required: ["id"],
                destructive: true
            ) { arguments in
                let existing = try project(try arguments.requiredID("id"))
                guard !existing.isInbox else { throw ToolError("The Inbox can't be deleted.") }
                let taskCount = try repository.tasks().count { $0.projectID == existing.id }
                try repository.deleteProject(id: existing.id)
                return ["deleted": .number(Double(existing.id)), "name": .string(existing.name), "tasks_deleted": .number(Double(taskCount))]
            }
        ]
    }
}
