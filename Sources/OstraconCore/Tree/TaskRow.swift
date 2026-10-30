import Foundation

/// A task positioned within a flattened, indented outline.
public struct TaskRow: Identifiable, Hashable, Sendable {
    public var task: TaskItem
    public var depth: Int
    public var childCount: Int

    public var id: Int64 { task.id }
    public var hasChildren: Bool { childCount > 0 }

    public init(task: TaskItem, depth: Int, childCount: Int) {
        self.task = task
        self.depth = depth
        self.childCount = childCount
    }
}
