import Foundation

/// A notification to deliver for a task.
public struct ScheduledReminder: Hashable, Sendable {
    public var taskID: Int64
    public var fireDate: Date

    /// Stable across reloads, so an unchanged reminder keeps its pending notification.
    public var identifier: String {
        "task-\(taskID)-\(Int(fireDate.timeIntervalSince1970))"
    }
}

public enum ReminderSchedule {
    /// The upcoming notifications for open tasks, soonest first.
    ///
    /// A task with a due time is always notified at that time, as well as at any reminders of its own.
    /// macOS keeps at most 64 pending notifications per app, so later ones wait for a future reschedule.
    public static func upcoming(
        for tasks: [TaskItem],
        after now: Date,
        calendar: Calendar = .current,
        limit: Int = 64
    ) -> [ScheduledReminder] {
        var scheduled = Set<ScheduledReminder>()
        for task in tasks where !task.isCompleted {
            var dates = task.reminders.compactMap { $0.fireDate(due: task.dueDate, calendar: calendar) }
            if let due = task.dueDate, due.hasTime {
                dates.append(due.date(in: calendar))
            }
            for date in dates where date > now {
                scheduled.insert(ScheduledReminder(taskID: task.id, fireDate: date))
            }
        }
        return Array(scheduled.sorted { ($0.fireDate, $0.taskID) < ($1.fireDate, $1.taskID) }.prefix(limit))
    }
}
