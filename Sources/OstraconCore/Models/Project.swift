import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public var color: ProjectColor
    public var sortOrder: Int
    public var isInbox: Bool

    public init(id: Int64, name: String, color: ProjectColor, sortOrder: Int, isInbox: Bool) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.isInbox = isInbox
    }
}
