import Foundation
import OstraconCore
import Testing

struct ReminderScheduleTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ id: Int64, due: DueDate? = nil, reminders: [Reminder] = [], completed: Bool = false) -> TaskItem {
        TaskItem(
            id: id, projectID: 1, parentID: nil, content: "Task \(id)", details: "", isCompleted: completed,
            completedAt: nil, sortOrder: 0, isCollapsed: false, createdAt: now, dueDate: due, reminders: reminders
        )
    }

    @Test func timedTasksRemindAtDueTimeAndBefore() {
        let due = DueDate(dayAndTime: now.addingTimeInterval(3600), calendar: calendar)
        let dueMoment = due.date(in: calendar)
        let schedule = ReminderSchedule.upcoming(
            for: [task(1, due: due, reminders: [.before(minutes: 30), .before(minutes: 0)])],
            after: now, calendar: calendar
        )
        #expect(schedule.map(\.fireDate) == [dueMoment.addingTimeInterval(-1800), dueMoment], "The due-time one isn't doubled")
    }

    @Test func skipsPastCompletedAndUntimedRelative() {
        let allDay = DueDate(day: now.addingTimeInterval(86_400 * 2), calendar: calendar)
        let schedule = ReminderSchedule.upcoming(
            for: [
                task(1, due: allDay, reminders: [.before(minutes: 10)]),
                task(2, reminders: [.at(now.addingTimeInterval(-60))]),
                task(3, reminders: [.at(now.addingTimeInterval(60))], completed: true),
                task(4, reminders: [.at(now.addingTimeInterval(120))])
            ],
            after: now, calendar: calendar
        )
        #expect(schedule.map(\.taskID) == [4])
    }

    @Test func keepsTheSoonest() {
        let tasks = (1...5).map { task(Int64($0), reminders: [.at(now.addingTimeInterval(Double(100 - $0)))]) }
        #expect(ReminderSchedule.upcoming(for: tasks, after: now, limit: 2).map(\.taskID) == [5, 4])
    }
}
