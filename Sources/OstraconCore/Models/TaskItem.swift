import Foundation

/// A to-do item. Named `TaskItem` to avoid clashing with Swift concurrency's `Task`.
public struct TaskItem: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var projectID: Int64
    public var parentID: Int64?
    public var content: String
    public var details: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var sortOrder: Int
    public var isCollapsed: Bool
    public var createdAt: Date

    public init(
        id: Int64,
        projectID: Int64,
        parentID: Int64?,
        content: String,
        details: String,
        isCompleted: Bool,
        completedAt: Date?,
        sortOrder: Int,
        isCollapsed: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.content = content
        self.details = details
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }
}
