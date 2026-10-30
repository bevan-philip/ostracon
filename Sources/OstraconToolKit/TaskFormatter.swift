import Foundation
import OstraconCore

/// Turns tasks into the JSON the tools return, from one snapshot of the database.
struct TaskFormatter {
    private let tasks: [TaskItem]
    private let projects: [Int64: Project]
    private let children: [Int64?: [TaskItem]]
    private let now: Date

    init(repository: TaskRepository, now: Date) throws {
        tasks = try repository.tasks()
        projects = Dictionary(uniqueKeysWithValues: try repository.projects().map { ($0.id, $0) })
        children = Dictionary(grouping: tasks, by: \.parentID)
            .mapValues { $0.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) } }
        self.now = now
    }

    /// Tasks depth-first in sidebar then sibling order, ignoring collapsing.
    /// Without `includeCompleted`, a completed task hides its subtasks too, as in the app.
    func outline(projectID: Int64?, includeCompleted: Bool) -> [(task: TaskItem, depth: Int)] {
        let projectOrder = projects.values.sorted { ($0.isInbox ? 0 : 1, $0.sortOrder, $0.id) < ($1.isInbox ? 0 : 1, $1.sortOrder, $1.id) }
        var rows: [(task: TaskItem, depth: Int)] = []
        func append(_ siblings: [TaskItem], depth: Int) {
            for task in siblings where includeCompleted || !task.isCompleted {
                rows.append((task, depth))
                append(children[task.id] ?? [], depth: depth + 1)
            }
        }
        for project in projectOrder where projectID == nil || project.id == projectID {
            append((children[nil] ?? []).filter { $0.projectID == project.id }, depth: 0)
        }
        return rows
    }

    func task(_ task: TaskItem, depth: Int? = nil, includingSubtasks: Bool = false) -> JSONValue {
        let subtasks = children[task.id] ?? []
        var object: [String: JSONValue] = [
            "id": .number(Double(task.id)),
            "content": .string(task.content),
            "project_id": .number(Double(task.projectID)),
            "project": .string(projects[task.projectID]?.name ?? ""),
            "parent_id": task.parentID.map { .number(Double($0)) } ?? .null,
            "completed": .bool(task.isCompleted),
            "due": task.dueDate.map { .string($0.storageValue) } ?? .null,
            "reminders": .array(task.reminders.map(reminder)),
            "created_at": .string(Self.timestamp(task.createdAt))
        ]
        if !task.details.isEmpty { object["details"] = .string(task.details) }
        if let completedAt = task.completedAt { object["completed_at"] = .string(Self.timestamp(completedAt)) }
        if let due = task.dueDate, !task.isCompleted { object["overdue"] = .bool(due.isOverdue(at: now)) }
        if let depth { object["depth"] = .number(Double(depth)) }
        if !subtasks.isEmpty {
            object["subtask_count"] = .number(Double(subtasks.count))
            object["completed_subtask_count"] = .number(Double(subtasks.count(where: \.isCompleted)))
        }
        if includingSubtasks {
            object["subtasks"] = .array(subtasks.map { self.task($0, includingSubtasks: true) })
        }
        return .object(object)
    }

    private func reminder(_ reminder: Reminder) -> JSONValue {
        switch reminder {
        case .at(let date): ["at": .string(Self.timestamp(date))]
        case .before(let minutes): ["minutes_before_due": .number(Double(minutes))]
        }
    }

    /// ISO 8601 in the user's time zone, so a model reads local times directly.
    private static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current))
    }
}
