import Foundation

/// A task positioned within a flattened, indented outline.
public struct TaskRow: Identifiable, Hashable, Sendable {
    public var task: TaskItem
    public var depth: Int
    /// Direct subtasks that are shown in the outline, ignoring collapsing.
    public var childCount: Int
    /// All direct subtasks, including completed ones that are hidden.
    public var subtaskCount: Int
    /// Direct subtasks that are completed, whether or not they are shown.
    public var completedSubtaskCount: Int

    public var id: Int64 { task.id }
    public var hasChildren: Bool { childCount > 0 }

    public init(task: TaskItem, depth: Int, childCount: Int, subtaskCount: Int = 0, completedSubtaskCount: Int = 0) {
        self.task = task
        self.depth = depth
        self.childCount = childCount
        self.subtaskCount = subtaskCount
        self.completedSubtaskCount = completedSubtaskCount
    }
}
