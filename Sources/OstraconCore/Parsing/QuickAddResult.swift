import Foundation

public struct QuickAddResult: Equatable, Sendable {
    /// The task text with any recognised `#Project` token removed.
    public var content: String
    /// The project named in the text, if any.
    public var projectID: Int64?

    public init(content: String, projectID: Int64?) {
        self.content = content
        self.projectID = projectID
    }
}
