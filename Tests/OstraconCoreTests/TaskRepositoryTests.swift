import Foundation
import OstraconCore
import Testing

struct TaskRepositoryTests {
    let repository: TaskRepository
    let inbox: Project

    init() throws {
        repository = try TaskRepository.inMemory()
        inbox = try repository.inbox()
    }

    private func rows(_ projectID: Int64? = nil, showCompleted: Bool = false) throws -> [String] {
        try TaskTree.rows(for: repository.tasks(), projectID: projectID ?? inbox.id, showCompleted: showCompleted)
            .map { String(repeating: "  ", count: $0.depth) + $0.task.content }
    }

    @Test func inboxIsCreatedOnce() throws {
        #expect(try repository.projects().map(\.name) == ["Inbox"])
        try repository.deleteProject(id: inbox.id)
        #expect(try repository.projects().count == 1, "The Inbox can't be deleted")
    }

    @Test func tasksAppendInOrder() throws {
        try repository.addTask(content: "One", projectID: inbox.id)
        try repository.addTask(content: "  Two  ", projectID: inbox.id)
        #expect(try rows() == ["One", "Two"])
        #expect(throws: RepositoryError.self) { try repository.addTask(content: "   ", projectID: inbox.id) }
    }

    @Test func indentAndOutdentBuildNesting() throws {
        let a = try repository.addTask(content: "A", projectID: inbox.id)
        let b = try repository.addTask(content: "B", projectID: inbox.id)
        let c = try repository.addTask(content: "C", projectID: inbox.id)

        #expect(try repository.indent(id: a.id) == false, "First task has nothing to indent under")
        try repository.indent(id: b.id)
        try repository.indent(id: c.id)
        try repository.indent(id: c.id)
        #expect(try rows() == ["A", "  B", "    C"])

        try repository.outdent(id: c.id)
        #expect(try rows() == ["A", "  B", "  C"])
        try repository.outdent(id: b.id)
        #expect(try rows() == ["A", "  C", "B"], "Outdented task becomes the sibling after its old parent")
    }

    @Test func moveSwapsWithSibling() throws {
        try repository.addTask(content: "A", projectID: inbox.id)
        let b = try repository.addTask(content: "B", projectID: inbox.id)
        try repository.move(id: b.id, by: -1)
        #expect(try rows() == ["B", "A"])
        #expect(try repository.move(id: b.id, by: -1) == false)
    }

    @Test func completingParentCompletesSubtree() throws {
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        let child = try repository.addTask(content: "Child", projectID: inbox.id, parentID: parent.id)
        try repository.addTask(content: "Other", projectID: inbox.id)

        try repository.setCompleted(id: parent.id, true)
        #expect(try rows() == ["Other"])
        #expect(try rows(showCompleted: true) == ["Parent", "  Child", "Other"])

        try repository.setCompleted(id: child.id, false)
        #expect(try rows() == ["Parent", "  Child", "Other"], "Reopening a child reopens its parent")
    }

    @Test func rowsCountCompletedSubtasksEvenWhenHidden() throws {
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        let done = try repository.addTask(content: "Done", projectID: inbox.id, parentID: parent.id)
        try repository.addTask(content: "Open", projectID: inbox.id, parentID: parent.id)
        try repository.addTask(content: "Grandchild", projectID: inbox.id, parentID: done.id)
        try repository.setCompleted(id: done.id, true)

        for showCompleted in [false, true] {
            let parentRow = try #require(
                TaskTree.rows(for: try repository.tasks(), projectID: inbox.id, showCompleted: showCompleted).first
            )
            #expect(parentRow.subtaskCount == 2, "Direct subtasks only")
            #expect(parentRow.completedSubtaskCount == 1)
            #expect(parentRow.childCount == (showCompleted ? 2 : 1))
        }
    }

    @Test func collapsedTasksHideChildren() throws {
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        try repository.addTask(content: "Child", projectID: inbox.id, parentID: parent.id)
        try repository.setCollapsed(id: parent.id, true)

        let tree = TaskTree.rows(for: try repository.tasks(), projectID: inbox.id, showCompleted: false)
        #expect(tree.map(\.task.content) == ["Parent"])
        #expect(tree.first?.childCount == 1)
    }

    @Test func movingTaskCarriesSubtasksToProject() throws {
        let work = try repository.createProject(name: "Work", color: .red)
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        let child = try repository.addTask(content: "Child", projectID: inbox.id, parentID: parent.id)
        let grandchild = try repository.addTask(content: "Grandchild", projectID: inbox.id, parentID: child.id)

        try repository.moveTask(id: child.id, toProject: work.id)
        #expect(try rows() == ["Parent"])
        #expect(try rows(work.id) == ["Child", "  Grandchild"])
        #expect(try repository.task(id: grandchild.id)?.projectID == work.id)
    }

    @Test func subtaskInAnotherProjectBecomesTopLevel() throws {
        let work = try repository.createProject(name: "Work", color: .red)
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        let task = try repository.addTask(content: "Elsewhere", projectID: work.id, parentID: parent.id)
        #expect(task.parentID == nil)
    }

    @Test func deletingCascades() throws {
        let work = try repository.createProject(name: "Work", color: .red)
        let parent = try repository.addTask(content: "Parent", projectID: work.id)
        try repository.addTask(content: "Child", projectID: work.id, parentID: parent.id)
        try repository.addTask(content: "Stays", projectID: inbox.id)

        try repository.deleteTask(id: parent.id)
        #expect(try rows(work.id).isEmpty)

        try repository.addTask(content: "Gone", projectID: work.id)
        try repository.deleteProject(id: work.id)
        #expect(try repository.tasks().map(\.content) == ["Stays"])
    }

    @Test func dataPersistsAcrossReopen() throws {
        let url = URL.temporaryDirectory.appending(path: "ostracon-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let first = try TaskRepository(database: SQLiteDatabase(path: url.path()))
            let work = try first.createProject(name: "Work", color: .grape)
            try first.addTask(content: "Persisted", projectID: work.id)
        }

        let second = try TaskRepository(database: SQLiteDatabase(path: url.path()))
        #expect(try second.projects().map(\.name) == ["Inbox", "Work"])
        #expect(try second.projects().last?.color == .grape)
        #expect(try second.tasks().map(\.content) == ["Persisted"])
    }

    @Test func dueDatesAndRemindersRoundTrip() throws {
        let due = DueDate(year: 2026, month: 11, day: 6, time: TimeOfDay(hour: 15, minute: 30))
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let task = try repository.addTask(
            content: "Dentist", projectID: inbox.id, dueDate: due,
            reminders: [.before(minutes: 30), .at(moment), .before(minutes: 30)]
        )
        var loaded = try #require(try repository.task(id: task.id))
        #expect(loaded.dueDate == due)
        #expect(loaded.reminders == [.at(moment), .before(minutes: 30)], "Duplicates are dropped, absolute first")

        try repository.setDueDate(id: task.id, DueDate(year: 2026, month: 12, day: 1))
        try repository.setReminders(id: task.id, [.before(minutes: 5)])
        loaded = try #require(try repository.task(id: task.id))
        #expect(loaded.dueDate == DueDate(year: 2026, month: 12, day: 1))
        #expect(loaded.reminders == [.before(minutes: 5)])

        try repository.setDueDate(id: task.id, nil)
        #expect(try repository.task(id: task.id)?.dueDate == nil)
    }

    @Test func deletingTaskDeletesItsReminders() throws {
        let task = try repository.addTask(content: "Remind me", projectID: inbox.id, reminders: [.before(minutes: 10)])
        try repository.deleteTask(id: task.id)
        let other = try repository.addTask(content: "Other", projectID: inbox.id)
        #expect(try repository.task(id: other.id)?.reminders == [])
    }

    @Test func noticesWritesFromAnotherConnection() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ostracon-\(UUID().uuidString).sqlite").path()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let app = try TaskRepository(database: SQLiteDatabase(path: path))
        let server = try TaskRepository(database: SQLiteDatabase(path: path))
        let inboxID = try app.inbox().id

        #expect(try app.hasExternalChanges() == false)
        try app.addTask(content: "Own write", projectID: inboxID)
        #expect(try app.hasExternalChanges() == false, "A connection's own writes don't count")

        try server.addTask(content: "From the MCP server", projectID: inboxID)
        #expect(try app.hasExternalChanges())
        #expect(try app.hasExternalChanges() == false, "Each change is reported once")
        #expect(try app.tasks().map(\.content) == ["Own write", "From the MCP server"])
    }

    @Test func dueDateStorageFormat() {
        #expect(DueDate(year: 2026, month: 1, day: 5).storageValue == "2026-01-05")
        let timed = DueDate(year: 2026, month: 1, day: 5, time: TimeOfDay(hour: 9, minute: 5))
        #expect(timed.storageValue == "2026-01-05T09:05")
        #expect(DueDate(storageValue: "2026-01-05T09:05") == timed)
        #expect(DueDate(storageValue: "nonsense") == nil)
    }
}
