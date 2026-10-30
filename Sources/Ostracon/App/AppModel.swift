import Foundation
import Observation
import OstraconCore

/// The app's shared state and the actions that change it.
@Observable
@MainActor
final class AppModel {
    private let repository: TaskRepository
    private let reminderScheduler: ReminderScheduling?

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

    init(repository: TaskRepository, reminderScheduler: ReminderScheduling? = nil) {
        self.repository = repository
        self.reminderScheduler = reminderScheduler
        reload()
        selectedProjectID = projects.first?.id
        reminderScheduler?.onResponse = { [weak self] response in
            self?.handle(response)
        }
    }

    /// Opens the on-disk database, falling back to a temporary in-memory one if that fails.
    static func makeDefault() -> AppModel {
        let notifier = ReminderNotifier.makeIfAvailable()
        do {
            return try AppModel(repository: .openDefault(), reminderScheduler: notifier)
        } catch {
            guard let fallback = try? TaskRepository.inMemory() else {
                fatalError("Unable to create even an in-memory SQLite database: \(error)")
            }
            let model = AppModel(repository: fallback, reminderScheduler: notifier)
            model.errorMessage = "Couldn't open your saved tasks (\(error.localizedDescription)). Changes this session won't be saved."
            return model
        }
    }

    // MARK: - Derived state

    /// The sidebar's selection. Choosing a project goes through `select(project:)`;
    /// deselecting is ignored so there is always a project on screen.
    var sidebarSelection: Int64? {
        get { selectedProjectID }
        set {
            guard let newValue, let project = project(id: newValue) else { return }
            select(project: project)
        }
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var inbox: Project? {
        projects.first(where: \.isInbox)
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
        let rows = rows
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

    /// The list items split into cards: each top-level task with its subtasks beneath it.
    var cardGroups: [TaskCardGroup] {
        var groups: [TaskCardGroup] = []
        for item in listItems {
            if item.depth == 0 || groups.isEmpty {
                groups.append(TaskCardGroup(id: Self.cardGroupID(for: item), items: [item]))
            } else {
                groups[groups.count - 1].items.append(item)
            }
        }
        return groups
    }

    private static func cardGroupID(for item: TaskListItem) -> String {
        switch item {
        case .task(let row): "card-\(row.id)"
        case .composer(.edit(let taskID), _): "card-\(taskID)"
        case .composer(.add, _): "card-new"
        }
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

    /// Notifications are turned off for the app, so reminders won't appear.
    var areRemindersBlocked: Bool {
        reminderScheduler?.isBlocked ?? false
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

    /// What the composer's draft would save, counting words not yet turned into blocks.
    func composerResult(for draft: QuickAddDraft, now: Date = .now) -> QuickAddResult {
        let dates = DateParser(now: now)
        return draft.converted(projects: projects, dates: dates, includingTrailing: true).result(dates: dates)
    }

    /// Saves plain composer text, as if it had been typed and submitted.
    @discardableResult
    func submitComposer(
        mode: ComposerMode,
        text: String,
        details: String,
        projectID: Int64,
        dueDate: DueDate? = nil,
        reminders: [Reminder] = []
    ) -> Bool {
        submitComposer(
            mode: mode, draft: QuickAddDraft(text: text), details: details,
            projectID: projectID, dueDate: dueDate, reminders: reminders
        )
    }

    /// Saves the composer's contents. Returns `true` on success.
    ///
    /// A project block in `draft` overrides `projectID`, a date block overrides `dueDate`,
    /// and reminder blocks are added to `reminders`.
    @discardableResult
    func submitComposer(
        mode: ComposerMode,
        draft: QuickAddDraft,
        details: String,
        projectID: Int64,
        dueDate: DueDate? = nil,
        reminders: [Reminder] = []
    ) -> Bool {
        let parsed = composerResult(for: draft)
        guard !parsed.content.isEmpty else { return false }
        let targetProjectID = parsed.projectID ?? projectID
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = parsed.dueDate ?? dueDate
        let reminders = reminders + parsed.reminders

        return perform {
            switch mode {
            case .add(let parentID):
                try repository.addTask(
                    content: parsed.content, details: details, projectID: targetProjectID, parentID: parentID,
                    dueDate: dueDate, reminders: reminders
                )
                if targetProjectID != selectedProjectID, let project = project(id: targetProjectID) {
                    toast = Toast(message: "Task added to \(project.name)")
                }
            case .edit(let taskID):
                try repository.updateTask(id: taskID, content: parsed.content, details: details)
                try repository.setDueDate(id: taskID, dueDate)
                try repository.setReminders(id: taskID, reminders)
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

    /// Reschedules a task, keeping its time of day unless `dueDate` brings its own.
    func setDueDate(_ taskID: Int64, _ dueDate: DueDate?) {
        let existingTime = task(id: taskID)?.dueDate?.time
        let dueDate = dueDate.map { $0.hasTime ? $0 : $0.withTime(existingTime) }
        perform { try repository.setDueDate(id: taskID, dueDate) }
    }

    /// Shows a task, e.g. after its notification is clicked: switches to its project and expands its ancestors.
    func reveal(_ taskID: Int64) {
        guard let task = task(id: taskID), let project = project(id: task.projectID) else { return }
        select(project: project)
        var ancestorID = task.parentID
        while let id = ancestorID, let ancestor = self.task(id: id) {
            if ancestor.isCollapsed {
                setCollapsed(id, false)
            }
            ancestorID = ancestor.parentID
        }
        if task.isCompleted {
            showCompleted = true
        }
        selectedTaskID = taskID
    }

    func handle(_ response: ReminderResponse) {
        switch response {
        case .open(let taskID):
            reveal(taskID)
        case .complete(let taskID):
            guard task(id: taskID)?.isCompleted == false else { return }
            moveSelectionOffRemovedTask(taskID)
            perform { try repository.setCompleted(id: taskID, true) }
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
            selectedProjectID = inbox?.id
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
        scheduleReminders()
    }

    /// Hands the upcoming reminders to the notifier. Cheap when nothing has changed.
    func scheduleReminders(now: Date = .now) {
        guard let reminderScheduler else { return }
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let notifications = ReminderSchedule.upcoming(for: tasks, after: now).compactMap { scheduled -> ReminderNotification? in
            guard let task = tasksByID[scheduled.taskID] else { return nil }
            var details: [String] = []
            if let due = task.dueDate {
                details.append(String(localized: "Due \(DueDateFormatter.string(for: due, now: scheduled.fireDate))"))
            }
            if let project = project(id: task.projectID) {
                details.append(project.name)
            }
            return ReminderNotification(
                identifier: scheduled.identifier, taskID: task.id, fireDate: scheduled.fireDate,
                title: task.content, body: details.joined(separator: " · ")
            )
        }
        reminderScheduler.schedule(notifications)
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
