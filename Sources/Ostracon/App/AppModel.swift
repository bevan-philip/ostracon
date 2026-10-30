import Foundation
import Observation
import OstraconCore

/// The app's shared state and the actions that change it.
@Observable
@MainActor
final class AppModel {
    private let repository: TaskRepository

    private(set) var projects: [Project] = []
    private(set) var tasks: [TaskItem] = []

    var selectedProjectID: Int64?
    var selectedTaskID: Int64?
    var showCompleted = false

    /// The inline composer, or `nil` when it is closed.
    var composer: ComposerMode?

    var projectDraft: ProjectDraft?
    var projectPendingDeletion: Project?
    var taskPendingDeletion: TaskItem?
    var toast: Toast?
    var errorMessage: String?

    init(repository: TaskRepository) {
        self.repository = repository
        reload()
        selectedProjectID = projects.first?.id
    }

    /// Opens the on-disk database, falling back to a temporary in-memory one if that fails.
    static func makeDefault() -> AppModel {
        do {
            return try AppModel(repository: .openDefault())
        } catch {
            guard let fallback = try? TaskRepository.inMemory() else {
                fatalError("Unable to create even an in-memory SQLite database: \(error)")
            }
            let model = AppModel(repository: fallback)
            model.errorMessage = "Couldn't open your saved tasks (\(error.localizedDescription)). Changes this session won't be saved."
            return model
        }
    }

    // MARK: - Derived state

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var isConfirmingProjectDeletion: Bool {
        get { projectPendingDeletion != nil }
        set { if !newValue { projectPendingDeletion = nil } }
    }

    var isConfirmingTaskDeletion: Bool {
        get { taskPendingDeletion != nil }
        set { if !newValue { taskPendingDeletion = nil } }
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var userProjects: [Project] {
        projects.filter { !$0.isInbox }
    }

    var rows: [TaskRow] {
        guard let selectedProjectID else { return [] }
        return TaskTree.rows(for: tasks, projectID: selectedProjectID, showCompleted: showCompleted)
    }

    /// The rows with the composer spliced in where it belongs.
    var listItems: [TaskListItem] {
        var items = rows.map(TaskListItem.task)
        switch composer {
        case nil:
            break
        case .add(parentID: nil):
            items.append(.composer(.add(parentID: nil), depth: 0))
        case .add(parentID: let parentID?):
            guard let parentIndex = rows.firstIndex(where: { $0.id == parentID }) else {
                items.append(.composer(.add(parentID: nil), depth: 0))
                break
            }
            let depth = rows[parentIndex].depth
            let end = rows[(parentIndex + 1)...].firstIndex { $0.depth <= depth } ?? rows.endIndex
            items.insert(.composer(.add(parentID: parentID), depth: depth + 1), at: end)
        case .edit(let taskID):
            if let index = rows.firstIndex(where: { $0.id == taskID }) {
                items[index] = .composer(.edit(taskID: taskID), depth: rows[index].depth)
            }
        }
        return items
    }

    func openCount(for project: Project) -> Int {
        TaskTree.openCount(in: tasks, projectID: project.id)
    }

    func task(id: Int64) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    func project(id: Int64) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Navigation

    func select(project: Project) {
        guard project.id != selectedProjectID else { return }
        selectedProjectID = project.id
        selectedTaskID = nil
        composer = nil
    }

    func selectProject(at index: Int) {
        guard projects.indices.contains(index) else { return }
        select(project: projects[index])
    }

    func moveSelection(by offset: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        guard let current = rows.firstIndex(where: { $0.id == selectedTaskID }) else {
            selectedTaskID = offset > 0 ? rows.first?.id : rows.last?.id
            return
        }
        let next = min(max(current + offset, 0), rows.count - 1)
        selectedTaskID = rows[next].id
    }

    // MARK: - Composer

    func startAddingTask() {
        composer = .add(parentID: nil)
    }

    func startAddingSubtask(to taskID: Int64? = nil) {
        guard let parentID = taskID ?? selectedTaskID else { return }
        if task(id: parentID)?.isCollapsed == true {
            setCollapsed(parentID, false)
        }
        composer = .add(parentID: parentID)
    }

    func startEditing(_ taskID: Int64? = nil) {
        guard let taskID = taskID ?? selectedTaskID else { return }
        selectedTaskID = taskID
        composer = .edit(taskID: taskID)
    }

    func closeComposer() {
        composer = nil
    }

    /// Saves the composer's contents. Returns `true` on success.
    ///
    /// `text` may contain a `#Project` token, which overrides `projectID`.
    @discardableResult
    func submitComposer(mode: ComposerMode, text: String, details: String, projectID: Int64) -> Bool {
        let parsed = QuickAddParser.parse(text, projects: projects)
        guard !parsed.content.isEmpty else { return false }
        let targetProjectID = parsed.projectID ?? projectID
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)

        return perform {
            switch mode {
            case .add(let parentID):
                try repository.addTask(
                    content: parsed.content, details: details, projectID: targetProjectID, parentID: parentID
                )
                if targetProjectID != selectedProjectID, let project = project(id: targetProjectID) {
                    toast = Toast(message: "Task added to \(project.name)")
                }
            case .edit(let taskID):
                try repository.updateTask(id: taskID, content: parsed.content, details: details)
                try repository.moveTask(id: taskID, toProject: targetProjectID)
                composer = nil
                if targetProjectID != selectedProjectID, let project = project(id: targetProjectID) {
                    selectedTaskID = nil
                    toast = Toast(message: "Task moved to \(project.name)")
                }
            }
        }
    }

    // MARK: - Task actions

    func toggleCompleted(_ taskID: Int64? = nil) {
        guard let taskID = taskID ?? selectedTaskID, let task = task(id: taskID) else { return }
        let completing = !task.isCompleted
        if completing && !showCompleted {
            moveSelectionOffRemovedTask(taskID)
        }
        perform {
            try repository.setCompleted(id: taskID, completing)
            if completing {
                toast = Toast(message: "1 task completed", undo: .reopen(taskID: taskID))
            }
        }
    }

    func requestDeletion(_ taskID: Int64? = nil) {
        guard let taskID = taskID ?? selectedTaskID else { return }
        taskPendingDeletion = task(id: taskID)
    }

    func confirmDeletion(_ task: TaskItem) {
        moveSelectionOffRemovedTask(task.id)
        if composer == .edit(taskID: task.id) {
            composer = nil
        }
        perform { try repository.deleteTask(id: task.id) }
    }

    func indent(_ taskID: Int64? = nil) {
        guard let taskID = taskID ?? selectedTaskID else { return }
        perform { try repository.indent(id: taskID) }
    }

    func outdent(_ taskID: Int64? = nil) {
        guard let taskID = taskID ?? selectedTaskID else { return }
        perform { try repository.outdent(id: taskID) }
    }

    func move(_ taskID: Int64? = nil, by offset: Int) {
        guard let taskID = taskID ?? selectedTaskID else { return }
        perform { try repository.move(id: taskID, by: offset) }
    }

    func move(_ taskID: Int64, toProject project: Project) {
        if task(id: taskID)?.projectID != project.id {
            moveSelectionOffRemovedTask(taskID)
        }
        perform {
            try repository.moveTask(id: taskID, toProject: project.id)
            toast = Toast(message: "Task moved to \(project.name)")
        }
    }

    func setCollapsed(_ taskID: Int64, _ isCollapsed: Bool) {
        perform { try repository.setCollapsed(id: taskID, isCollapsed) }
    }

    /// Left arrow: collapse the selected task, or jump to its parent if it is already collapsed or a leaf.
    func collapseOrSelectParent() {
        guard let row = rows.first(where: { $0.id == selectedTaskID }) else { return }
        if row.hasChildren && !row.task.isCollapsed {
            setCollapsed(row.id, true)
        } else if let parentID = row.task.parentID {
            selectedTaskID = parentID
        }
    }

    /// Right arrow: expand the selected task.
    func expandSelected() {
        guard let task = selectedTaskID.flatMap(task(id:)), task.isCollapsed else { return }
        setCollapsed(task.id, false)
    }

    func performUndo(for toast: Toast) {
        switch toast.undo {
        case .reopen(let taskID):
            perform { try repository.setCompleted(id: taskID, false) }
        case nil:
            break
        }
        self.toast = nil
    }

    func dismissToast(_ toast: Toast) {
        if self.toast == toast {
            self.toast = nil
        }
    }

    // MARK: - Projects

    func startCreatingProject() {
        projectDraft = .new
    }

    func startEditing(_ project: Project) {
        projectDraft = ProjectDraft(projectID: project.id, name: project.name, color: project.color)
    }

    func saveProjectDraft(_ draft: ProjectDraft) {
        perform {
            if let projectID = draft.projectID {
                try repository.updateProject(id: projectID, name: draft.name, color: draft.color)
            } else {
                let project = try repository.createProject(name: draft.name, color: draft.color)
                selectedProjectID = project.id
                selectedTaskID = nil
                composer = nil
            }
            projectDraft = nil
        }
    }

    func confirmDeletion(_ project: Project) {
        if selectedProjectID == project.id {
            selectedProjectID = projects.first(where: \.isInbox)?.id
            selectedTaskID = nil
            composer = nil
        }
        perform { try repository.deleteProject(id: project.id) }
    }

    // MARK: - Helpers

    func reload() {
        do {
            projects = try repository.projects()
            tasks = try repository.tasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Runs a repository change, reloads, and surfaces any error. Returns `true` on success.
    @discardableResult
    private func perform(_ change: () throws -> Void) -> Bool {
        defer { reload() }
        do {
            try change()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Before a task disappears from the list, select the row after its subtree (or the one before).
    private func moveSelectionOffRemovedTask(_ taskID: Int64) {
        guard selectedTaskID == taskID else { return }
        let rows = rows
        guard let index = rows.firstIndex(where: { $0.id == taskID }) else { return }
        let depth = rows[index].depth
        let after = rows[(index + 1)...].first { $0.depth <= depth }
        let before = index > 0 ? rows[index - 1] : nil
        selectedTaskID = (after ?? before)?.id
    }
}
