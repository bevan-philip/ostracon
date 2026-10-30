import Foundation

public enum TaskTree {
    /// Flattens a project's tasks into display order, depth-first.
    ///
    /// Collapsed tasks hide their descendants. Unless `showCompleted` is set, completed tasks
    /// (and therefore everything beneath them) are left out.
    public static func rows(for tasks: [TaskItem], projectID: Int64, showCompleted: Bool) -> [TaskRow] {
        let projectTasks = tasks.filter { $0.projectID == projectID }
        let visible = projectTasks.filter { showCompleted || !$0.isCompleted }
        let children = Dictionary(grouping: visible, by: \.parentID)
            .mapValues { $0.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) } }
        // Counted from every task, so a parent can say how many subtasks are done even while they're hidden.
        let allChildren = Dictionary(grouping: projectTasks, by: \.parentID)

        var rows: [TaskRow] = []
        func append(parentID: Int64?, depth: Int) {
            for task in children[parentID] ?? [] {
                let subtasks = allChildren[task.id] ?? []
                rows.append(TaskRow(
                    task: task,
                    depth: depth,
                    childCount: children[task.id]?.count ?? 0,
                    subtaskCount: subtasks.count,
                    completedSubtaskCount: subtasks.count(where: \.isCompleted)
                ))
                if !task.isCollapsed {
                    append(parentID: task.id, depth: depth + 1)
                }
            }
        }
        append(parentID: nil, depth: 0)
        return rows
    }

    /// The number of open tasks in a project, including subtasks.
    public static func openCount(in tasks: [TaskItem], projectID: Int64) -> Int {
        tasks.count { $0.projectID == projectID && !$0.isCompleted }
    }
}
