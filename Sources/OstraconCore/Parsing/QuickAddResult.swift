import Foundation

public struct QuickAddResult: Equatable, Sendable {
    /// The task text with any recognised `#Project`, date and `!reminder` removed.
    public var content: String
    /// The project named in the text, if any.
    public var projectID: Int64?
    /// The due date written in the text, if any.
    public var dueDate: DueDate?
    /// Reminders written in the text with `!`.
    public var reminders: [Reminder]
    /// The words that set the due date, as typed.
    public var dueText: String?

    public init(
        content: String,
        projectID: Int64?,
        dueDate: DueDate? = nil,
        reminders: [Reminder] = [],
        dueText: String? = nil
    ) {
        self.content = content
        self.projectID = projectID
        self.dueDate = dueDate
        self.reminders = reminders
        self.dueText = dueText
    }
}
