import Foundation

/// When to notify about a task.
public enum Reminder: Hashable, Sendable {
    /// At a fixed moment.
    case at(Date)
    /// A number of minutes before the task's due time. Has no effect on tasks without one.
    case before(minutes: Int)

    /// When this reminder goes off for a task due at `due`, or `nil` if it can't.
    public func fireDate(due: DueDate?, calendar: Calendar = .current) -> Date? {
        switch self {
        case .at(let date):
            date
        case .before(let minutes):
            due.flatMap { $0.hasTime ? $0.date(in: calendar).addingTimeInterval(Double(-minutes) * 60) : nil }
        }
    }

    /// Absolute reminders first, in time order, then relative ones from the latest to the earliest.
    public static func sorted(_ reminders: [Reminder]) -> [Reminder] {
        reminders.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (.at(let a), .at(let b)): a < b
            case (.before(let a), .before(let b)): a < b
            case (.at, .before): true
            case (.before, .at): false
            }
        }
    }
}
