@testable import Ostracon
import OstraconCore
import Testing

@MainActor
struct AppModelTests {
    let model: AppModel
    let inboxID: Int64

    init() throws {
        model = AppModel(repository: try TaskRepository.inMemory())
        inboxID = try #require(model.selectedProjectID)
    }

    private var contents: [String] {
        model.rows.map { String(repeating: "  ", count: $0.depth) + $0.task.content }
    }

    private func createProject(_ name: String) throws -> Project {
        model.saveProjectDraft(ProjectDraft(projectID: nil, name: name, color: .red))
        let project = try #require(model.projects.first { $0.name == name })
        model.select(project: try #require(model.project(id: inboxID)))
        return project
    }

    @Test func composerStaysOpenForRapidEntry() {
        model.startAddingTask()
        #expect(model.submitComposer(mode: .add(parentID: nil), text: "First", details: "", projectID: inboxID))
        #expect(model.submitComposer(mode: .add(parentID: nil), text: "Second", details: "", projectID: inboxID))
        #expect(model.composer == .add(parentID: nil))
        #expect(contents == ["First", "Second"])
        #expect(!model.submitComposer(mode: .add(parentID: nil), text: "   ", details: "", projectID: inboxID))
    }

    @Test func hashtagFilesTaskIntoProjectAndShowsToast() throws {
        let work = try createProject("Work")
        model.submitComposer(mode: .add(parentID: nil), text: "Write report #work", details: "", projectID: inboxID)

        #expect(contents.isEmpty, "Task went to Work, not the Inbox")
        #expect(model.tasks.first?.projectID == work.id)
        #expect(model.tasks.first?.content == "Write report")
        #expect(model.toast?.message == "Task added to Work")
    }

    @Test func editingWithHashtagMovesTask() throws {
        let home = try createProject("Home")
        model.submitComposer(mode: .add(parentID: nil), text: "Water plants", details: "", projectID: inboxID)
        let taskID = try #require(model.rows.first?.id)

        model.startEditing(taskID)
        model.submitComposer(mode: .edit(taskID: taskID), text: "Water the plants #Home", details: "Weekly", projectID: inboxID)
        #expect(model.composer == nil)
        #expect(model.task(id: taskID)?.projectID == home.id)
        #expect(model.task(id: taskID)?.content == "Water the plants")
        #expect(model.task(id: taskID)?.details == "Weekly")
    }

    @Test func subtaskComposerSitsAfterParentSubtree() throws {
        for name in ["A", "B"] {
            model.submitComposer(mode: .add(parentID: nil), text: name, details: "", projectID: inboxID)
        }
        let a = try #require(model.rows.first?.id)
        model.submitComposer(mode: .add(parentID: a), text: "A1", details: "", projectID: inboxID)

        model.startAddingSubtask(to: a)
        let ids = model.listItems.map(\.id)
        #expect(ids.count == 4)
        #expect(ids[2] == "composer", "Composer goes after A's existing subtask and before B")
        #expect(model.listItems[2] == .composer(.add(parentID: a), depth: 1))
    }

    @Test func keyboardSelectionAndOutlining() throws {
        for name in ["A", "B", "C"] {
            model.submitComposer(mode: .add(parentID: nil), text: name, details: "", projectID: inboxID)
        }
        model.closeComposer()

        model.moveSelection(by: 1)
        #expect(model.selectedTaskID == model.rows[0].id)
        model.moveSelection(by: 1)
        model.indent()
        #expect(contents == ["A", "  B", "C"])
        model.moveSelection(by: 5)
        #expect(model.selectedTaskID == model.rows[2].id, "Selection clamps at the end")

        model.moveSelection(by: -1)
        model.collapseOrSelectParent()
        #expect(model.selectedTaskID == model.rows[0].id, "Left arrow on a leaf jumps to its parent")
        model.collapseOrSelectParent()
        #expect(contents == ["A", "C"], "Left arrow on an open parent collapses it")
        model.expandSelected()
        #expect(contents == ["A", "  B", "C"])
    }

    @Test func completingMovesSelectionAndCanBeUndone() throws {
        for name in ["A", "B"] {
            model.submitComposer(mode: .add(parentID: nil), text: name, details: "", projectID: inboxID)
        }
        let a = model.rows[0].id
        model.selectedTaskID = a

        model.toggleCompleted()
        #expect(contents == ["B"])
        #expect(model.selectedTaskID == model.rows.first?.id)

        let toast = try #require(model.toast)
        model.performUndo(for: toast)
        #expect(contents == ["A", "B"])
        #expect(model.toast == nil)
    }

    @Test func deletingSelectedProjectReturnsToInbox() throws {
        let work = try createProject("Work")
        model.select(project: work)
        model.confirmDeletion(work)
        #expect(model.selectedProjectID == inboxID)
        #expect(model.userProjects.isEmpty)
    }
}
