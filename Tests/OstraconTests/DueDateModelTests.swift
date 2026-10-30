@testable import Ostracon
import Foundation
import OstraconCore
import Testing

@MainActor
final class FakeReminderScheduler: ReminderScheduling {
    var scheduled: [ReminderNotification] = []
    var onResponse: ((ReminderResponse) -> Void)?
    var isBlocked = false

    func schedule(_ notifications: [ReminderNotification]) {
        scheduled = notifications
    }
}

@MainActor
struct DueDateModelTests {
    let scheduler = FakeReminderScheduler()
    let model: AppModel
    let inboxID: Int64

    init() throws {
        model = AppModel(repository: try TaskRepository.inMemory(), reminderScheduler: scheduler)
        inboxID = try #require(model.selectedProjectID)
    }

    private var tomorrow: DueDate {
        DueDate(day: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
    }

    private func add(_ text: String, dueDate: DueDate? = nil, reminders: [Reminder] = []) throws -> TaskItem {
        try add(QuickAddDraft(text: text), dueDate: dueDate, reminders: reminders)
    }

    private func add(_ draft: QuickAddDraft, dueDate: DueDate? = nil, reminders: [Reminder] = []) throws -> TaskItem {
        #expect(model.submitComposer(
            mode: .add(parentID: nil), draft: draft, details: "", projectID: inboxID,
            dueDate: dueDate, reminders: reminders
        ))
        return try #require(model.tasks.last)
    }

    @Test func typedDatesAndRemindersAreSaved() throws {
        let task = try add("Call mum tomorrow at 5pm !30min")
        #expect(task.content == "Call mum")
        #expect(task.dueDate == tomorrow.withTime(TimeOfDay(hour: 17)))
        #expect(task.reminders == [.before(minutes: 30)])
    }

    @Test func typedDateBeatsPickedDateAndRemindersCombine() throws {
        let task = try add("Pay rent tomorrow !1h", dueDate: DueDate(year: 2030, month: 1, day: 1), reminders: [.before(minutes: 5)])
        #expect(task.dueDate == tomorrow)
        #expect(task.reminders == [.before(minutes: 5), .before(minutes: 60)])
    }

    @Test func revertedBlocksStayInTheName() throws {
        let draft = QuickAddDraft(segments: [
            .text("Read ", isLiteral: false), .text("Today", isLiteral: true), .text(" magazine", isLiteral: false)
        ])
        let task = try add(draft)
        #expect(task.content == "Read Today magazine")
        #expect(task.dueDate == nil)

        let other = try add(QuickAddDraft(segments: draft.segments + [.text(" tomorrow", isLiteral: false)]))
        #expect(other.dueDate == tomorrow, "A different date is still recognised")
        #expect(other.content == "Read Today magazine")
    }

    @Test func editingKeepsDateWordsInExistingNames() throws {
        let task = try add("Plan launch")
        model.submitComposer(
            mode: .edit(taskID: task.id), draft: QuickAddDraft(text: "Plan Monday launch", isLiteral: true),
            details: "", projectID: inboxID
        )
        #expect(model.task(id: task.id)?.content == "Plan Monday launch")
        #expect(model.task(id: task.id)?.dueDate == nil)
    }

    @Test func editingReplacesDateAndReminders() throws {
        let task = try add("Dentist tomorrow 3pm !10min")
        model.submitComposer(mode: .edit(taskID: task.id), text: "Dentist", details: "", projectID: inboxID, dueDate: nil, reminders: [])
        let edited = try #require(model.task(id: task.id))
        #expect(edited.dueDate == nil)
        #expect(edited.reminders.isEmpty)
    }

    @Test func reschedulingKeepsTheTime() throws {
        let task = try add("Standup tomorrow 9:30am")
        let today = try #require(DueDateShortcut.today.dueDate())
        model.setDueDate(task.id, today)
        #expect(model.task(id: task.id)?.dueDate == today.withTime(TimeOfDay(hour: 9, minute: 30)))
        model.setDueDate(task.id, nil)
        #expect(model.task(id: task.id)?.dueDate == nil)
    }

    @Test func remindersAreScheduledAndClearedOnCompletion() throws {
        let task = try add("Dentist tomorrow 3pm !1h")
        #expect(scheduler.scheduled.count == 2, "One hour before, and at the due time")
        #expect(scheduler.scheduled.allSatisfy { $0.title == "Dentist" && $0.taskID == task.id })
        #expect(scheduler.scheduled.first?.body.hasPrefix("Due Today") == true, "Worded from when it fires")

        scheduler.onResponse?(.complete(taskID: task.id))
        #expect(model.task(id: task.id)?.isCompleted == true)
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func openingANotificationRevealsTheTask() throws {
        model.saveProjectDraft(ProjectDraft(projectID: nil, name: "Work", color: .red))
        let work = try #require(model.projects.first { $0.name == "Work" })
        let parent = try add("Parent #Work")
        model.startAddingSubtask(to: parent.id)
        model.submitComposer(mode: .add(parentID: parent.id), text: "Child", details: "", projectID: work.id)
        let child = try #require(model.tasks.last)
        model.setCollapsed(parent.id, true)
        model.select(project: try #require(model.inbox))

        scheduler.onResponse?(.open(taskID: child.id))
        #expect(model.selectedProjectID == work.id)
        #expect(model.selectedTaskID == child.id)
        #expect(model.rows.map(\.id).contains(child.id))
    }
}
