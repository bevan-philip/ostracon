import OstraconCore
import SwiftUI

/// A task's due date in its urgency colour, and a bell if it has reminders.
struct TaskDueLabel: View {
    let task: TaskItem

    static func hasContent(for task: TaskItem) -> Bool {
        task.dueDate != nil || !task.reminders.isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            if let due = task.dueDate {
                // Ticks over so "Today" becomes overdue, or "Tomorrow" becomes "Today", without a reload.
                TimelineView(.everyMinute) { context in
                    Label(DueDateFormatter.string(for: due, now: context.date), systemImage: "calendar")
                        .foregroundStyle(task.isCompleted ? AnyShapeStyle(.tertiary) : Theme.style(for: DueUrgency(due, now: context.date)))
                }
            }
            if !task.reminders.isEmpty {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                    .help(task.reminders.map { DueDateFormatter.string(for: $0) }.formatted(.list(type: .and)))
                    .accessibilityLabel(task.reminders.count == 1 ? "1 reminder" : "\(task.reminders.count) reminders")
            }
        }
        .font(.callout)
    }
}
