import OstraconCore

/// One line of the task list: either a task or the inline composer.
enum TaskListItem: Identifiable, Equatable {
    case task(TaskRow)
    case composer(ComposerMode, depth: Int)

    var id: String {
        switch self {
        case .task(let row): "task-\(row.id)"
        case .composer: "composer"
        }
    }

    var depth: Int {
        switch self {
        case .task(let row): row.depth
        case .composer(_, let depth): depth
        }
    }
}
