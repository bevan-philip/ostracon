import Foundation

/// All persistence for projects and tasks.
public final class TaskRepository {
    private let database: SQLiteDatabase
    private var lastDataVersion: Int64?

    /// The database file, or `nil` for one in memory.
    public let url: URL?

    public init(database: SQLiteDatabase, url: URL? = nil) throws {
        self.database = database
        self.url = url
        try Schema.migrate(database)
        try ensureInbox()
        lastDataVersion = try dataVersion()
    }

    /// Whether another connection, such as the MCP server, has committed changes since this was last asked.
    public func hasExternalChanges() throws -> Bool {
        let version = try dataVersion()
        defer { lastDataVersion = version }
        return version != lastDataVersion
    }

    /// Opens the repository stored in the user's Application Support folder,
    /// or at the path in the `OSTRACON_DATABASE` environment variable if set.
    public static func openDefault() throws -> TaskRepository {
        if let path = ProcessInfo.processInfo.environment["OSTRACON_DATABASE"], !path.isEmpty {
            return try open(URL(filePath: path))
        }
        let folder = URL.applicationSupportDirectory.appending(path: "Ostracon", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try open(folder.appending(path: "ostracon.sqlite"))
    }

    /// Opens (creating if needed) the database file at `url`.
    public static func open(_ url: URL) throws -> TaskRepository {
        try TaskRepository(database: SQLiteDatabase(path: url.path(percentEncoded: false)), url: url)
    }

    /// An empty in-memory repository, for tests and previews.
    public static func inMemory() throws -> TaskRepository {
        try TaskRepository(database: SQLiteDatabase(path: ":memory:"))
    }

    // MARK: - Copies

    /// When anything, from this connection or another, last wrote to the database file.
    public func lastModified() -> Date? {
        guard let url else { return nil }
        // Commits land in the write-ahead log, and reach the main file only when the log is checkpointed.
        let files = [url, URL(filePath: url.path(percentEncoded: false) + "-wal")]
        return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    /// Writes a consistent copy of every project and task to a new file at `url`.
    public func copy(to url: URL) throws {
        try database.copy(to: url.path(percentEncoded: false))
    }

    /// Replaces every project and task with those in the Ostracon database at `url`, such as a backup.
    /// Other connections, like the app's, see this as an ordinary change.
    public func restore(from url: URL) throws {
        let source = try SQLiteDatabase(path: url.path(percentEncoded: false), readOnly: true)
        let tables = (try? source.query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.text(0) }) ?? []
        guard Set(tables).isSuperset(of: ["projects", "tasks"]) else {
            throw RepositoryError.notADatabase(url)
        }
        try database.replaceContents(with: source)
        try Schema.migrate(database)
        try ensureInbox()
    }

    // MARK: - Projects

    /// All projects, Inbox first, then in sidebar order.
    public func projects() throws -> [Project] {
        try database.query(
            "SELECT id, name, color, sort_order, is_inbox FROM projects ORDER BY is_inbox DESC, sort_order, id"
        ) { row in
            Project(
                id: row.int(0),
                name: row.text(1),
                color: ProjectColor(rawValue: row.text(2)) ?? .charcoal,
                sortOrder: Int(row.int(3)),
                isInbox: row.bool(4)
            )
        }
    }

    public func inbox() throws -> Project {
        guard let inbox = try projects().first(where: \.isInbox) else {
            throw RepositoryError.missingInbox
        }
        return inbox
    }

    @discardableResult
    public func createProject(name: String, color: ProjectColor) throws -> Project {
        let name = try validatedName(name)
        let order = try nextOrder("SELECT MAX(sort_order) FROM projects WHERE is_inbox = 0")
        try database.run(
            "INSERT INTO projects (name, color, sort_order) VALUES (?, ?, ?)",
            .text(name), .text(color.rawValue), .integer(Int64(order))
        )
        return Project(id: database.lastInsertRowID, name: name, color: color, sortOrder: order, isInbox: false)
    }

    public func updateProject(id: Int64, name: String, color: ProjectColor) throws {
        try database.run(
            "UPDATE projects SET name = ?, color = ? WHERE id = ? AND is_inbox = 0",
            .text(try validatedName(name)), .text(color.rawValue), .integer(id)
        )
    }

    /// Deletes a project and all of its tasks. The Inbox cannot be deleted.
    public func deleteProject(id: Int64) throws {
        try database.run("DELETE FROM projects WHERE id = ? AND is_inbox = 0", .integer(id))
    }

    // MARK: - Tasks

    /// Every task, in sibling order.
    public func tasks() throws -> [TaskItem] {
        let reminders = try remindersByTask()
        return try database.query(
            """
            SELECT id, project_id, parent_id, content, details, is_completed, completed_at,
                   sort_order, is_collapsed, created_at, due
            FROM tasks ORDER BY sort_order, id
            """
        ) { row in
            let id = row.int(0)
            return TaskItem(
                id: id,
                projectID: row.int(1),
                parentID: row.optionalInt(2),
                content: row.text(3),
                details: row.text(4),
                isCompleted: row.bool(5),
                completedAt: row.optionalDouble(6).map(Date.init(timeIntervalSince1970:)),
                sortOrder: Int(row.int(7)),
                isCollapsed: row.bool(8),
                createdAt: Date(timeIntervalSince1970: row.double(9)),
                dueDate: row.optionalText(10).flatMap(DueDate.init(storageValue:)),
                reminders: reminders[id] ?? []
            )
        }
    }

    public func task(id: Int64) throws -> TaskItem? {
        try tasks().first { $0.id == id }
    }

    /// Adds a task at the end of its siblings.
    ///
    /// If `parentID` belongs to a different project, the task is added at the top level of `projectID` instead.
    @discardableResult
    public func addTask(
        content: String,
        details: String = "",
        projectID: Int64,
        parentID: Int64? = nil,
        dueDate: DueDate? = nil,
        reminders: [Reminder] = []
    ) throws -> TaskItem {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw RepositoryError.emptyName }

        var parentID = parentID
        if let parent = parentID, try self.projectID(ofTask: parent) != projectID {
            parentID = nil
        }

        let order = try nextSiblingOrder(projectID: projectID, parentID: parentID)
        let now = Date.now
        let id = try database.transaction {
            try database.run(
                """
                INSERT INTO tasks (project_id, parent_id, content, details, sort_order, created_at, due)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                .integer(projectID), .optional(parentID), .text(content), .text(details),
                .integer(Int64(order)), .real(now.timeIntervalSince1970), .optional(dueDate?.storageValue)
            )
            let id = database.lastInsertRowID
            try insertReminders(reminders, taskID: id)
            return id
        }
        return TaskItem(
            id: id, projectID: projectID, parentID: parentID, content: content, details: details,
            isCompleted: false, completedAt: nil, sortOrder: order, isCollapsed: false, createdAt: now,
            dueDate: dueDate, reminders: Reminder.sorted(reminders)
        )
    }

    public func updateTask(id: Int64, content: String, details: String) throws {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw RepositoryError.emptyName }
        try database.run(
            "UPDATE tasks SET content = ?, details = ? WHERE id = ?",
            .text(content), .text(details), .integer(id)
        )
    }

    public func setDueDate(id: Int64, _ dueDate: DueDate?) throws {
        try database.run("UPDATE tasks SET due = ? WHERE id = ?", .optional(dueDate?.storageValue), .integer(id))
    }

    /// Replaces all of a task's reminders.
    public func setReminders(id: Int64, _ reminders: [Reminder]) throws {
        try database.transaction {
            try database.run("DELETE FROM reminders WHERE task_id = ?", .integer(id))
            try insertReminders(reminders, taskID: id)
        }
    }

    /// Moves a task, with its subtasks, to the end of another project's top level.
    public func moveTask(id: Int64, toProject projectID: Int64) throws {
        guard try self.projectID(ofTask: id) != projectID else { return }
        try database.transaction {
            let order = try nextSiblingOrder(projectID: projectID, parentID: nil)
            try database.run(
                "UPDATE tasks SET parent_id = NULL, sort_order = ? WHERE id = ?",
                .integer(Int64(order)), .integer(id)
            )
            for taskID in try subtreeIDs(of: id) {
                try database.run("UPDATE tasks SET project_id = ? WHERE id = ?", .integer(projectID), .integer(taskID))
            }
        }
    }

    /// Completing a task also completes its subtasks, as in Todoist.
    /// Reopening a task also reopens any completed ancestors so it becomes visible again.
    public func setCompleted(id: Int64, _ isCompleted: Bool) throws {
        try database.transaction {
            if isCompleted {
                let now = Date.now.timeIntervalSince1970
                for taskID in try subtreeIDs(of: id) {
                    try database.run(
                        "UPDATE tasks SET is_completed = 1, completed_at = COALESCE(completed_at, ?) WHERE id = ?",
                        .real(now), .integer(taskID)
                    )
                }
            } else {
                var current: Int64? = id
                while let taskID = current {
                    try database.run(
                        "UPDATE tasks SET is_completed = 0, completed_at = NULL WHERE id = ?",
                        .integer(taskID)
                    )
                    current = try parentID(ofTask: taskID)
                }
            }
        }
    }

    /// Deletes a task and its subtasks.
    public func deleteTask(id: Int64) throws {
        try database.run("DELETE FROM tasks WHERE id = ?", .integer(id))
    }

    public func setCollapsed(id: Int64, _ isCollapsed: Bool) throws {
        try database.run("UPDATE tasks SET is_collapsed = ? WHERE id = ?", .bool(isCollapsed), .integer(id))
    }

    /// Makes a task the last subtask of the open sibling directly above it.
    /// Returns `false` when there is no such sibling.
    @discardableResult
    public func indent(id: Int64) throws -> Bool {
        guard let task = try task(id: id) else { return false }
        let siblings = try openSiblings(projectID: task.projectID, parentID: task.parentID)
        guard let index = siblings.firstIndex(of: id), index > 0 else { return false }
        let newParent = siblings[index - 1]
        let order = try nextSiblingOrder(projectID: task.projectID, parentID: newParent)
        try database.transaction {
            try database.run(
                "UPDATE tasks SET parent_id = ?, sort_order = ? WHERE id = ?",
                .integer(newParent), .integer(Int64(order)), .integer(id)
            )
            try database.run("UPDATE tasks SET is_collapsed = 0 WHERE id = ?", .integer(newParent))
        }
        return true
    }

    /// Moves a subtask up one level, placing it directly after its former parent.
    /// Returns `false` for top-level tasks.
    @discardableResult
    public func outdent(id: Int64) throws -> Bool {
        guard let task = try task(id: id), let parentID = task.parentID, let parent = try self.task(id: parentID) else {
            return false
        }
        var siblings = try allSiblings(projectID: parent.projectID, parentID: parent.parentID)
        guard let parentIndex = siblings.firstIndex(of: parentID) else { return false }
        siblings.insert(id, at: parentIndex + 1)
        try database.transaction {
            try database.run("UPDATE tasks SET parent_id = ? WHERE id = ?", .optional(parent.parentID), .integer(id))
            try renumber(siblings)
        }
        return true
    }

    /// Swaps a task with its previous (`offset == -1`) or next (`offset == 1`) open sibling.
    @discardableResult
    public func move(id: Int64, by offset: Int) throws -> Bool {
        guard let task = try task(id: id) else { return false }
        let open = try openSiblings(projectID: task.projectID, parentID: task.parentID)
        guard let index = open.firstIndex(of: id), open.indices.contains(index + offset) else { return false }
        let neighbour = open[index + offset]

        var siblings = try allSiblings(projectID: task.projectID, parentID: task.parentID)
        guard let from = siblings.firstIndex(of: id), let to = siblings.firstIndex(of: neighbour) else { return false }
        siblings.swapAt(from, to)
        try database.transaction { try renumber(siblings) }
        return true
    }

    // MARK: - Helpers

    /// Changes whenever another connection commits; this connection's own writes leave it alone.
    private func dataVersion() throws -> Int64 {
        try database.query("PRAGMA data_version") { $0.int(0) }.first ?? 0
    }

    private func ensureInbox() throws {
        let count = try database.query("SELECT COUNT(*) FROM projects WHERE is_inbox = 1") { $0.int(0) }.first ?? 0
        if count == 0 {
            try database.run(
                "INSERT INTO projects (name, color, sort_order, is_inbox) VALUES ('Inbox', ?, 0, 1)",
                .text(ProjectColor.blue.rawValue)
            )
        }
    }

    private func remindersByTask() throws -> [Int64: [Reminder]] {
        let pairs = try database.query("SELECT task_id, fire_at, minutes_before FROM reminders") { row -> (Int64, Reminder)? in
            if let fireAt = row.optionalDouble(1) {
                return (row.int(0), .at(Date(timeIntervalSince1970: fireAt)))
            }
            if let minutes = row.optionalInt(2) {
                return (row.int(0), .before(minutes: Int(minutes)))
            }
            return nil
        }
        return Dictionary(grouping: pairs.compactMap(\.self), by: \.0).mapValues { Reminder.sorted($0.map(\.1)) }
    }

    /// Adds reminders to a task, skipping duplicates.
    private func insertReminders(_ reminders: [Reminder], taskID: Int64) throws {
        for reminder in Set(reminders) {
            switch reminder {
            case .at(let date):
                try database.run(
                    "INSERT INTO reminders (task_id, fire_at) VALUES (?, ?)",
                    .integer(taskID), .real(date.timeIntervalSince1970)
                )
            case .before(let minutes):
                try database.run(
                    "INSERT INTO reminders (task_id, minutes_before) VALUES (?, ?)",
                    .integer(taskID), .integer(Int64(minutes))
                )
            }
        }
    }

    private func validatedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RepositoryError.emptyName }
        return name
    }

    private func nextOrder(_ sql: String) throws -> Int {
        let maximum = try database.query(sql) { $0.optionalInt(0) }
        return Int((maximum.first ?? nil) ?? -1) + 1
    }

    private func nextSiblingOrder(projectID: Int64, parentID: Int64?) throws -> Int {
        let maximum = try database.query(
            "SELECT MAX(sort_order) FROM tasks WHERE project_id = ? AND parent_id IS ?",
            .integer(projectID), .optional(parentID)
        ) { $0.optionalInt(0) }
        return Int((maximum.first ?? nil) ?? -1) + 1
    }

    private func allSiblings(projectID: Int64, parentID: Int64?) throws -> [Int64] {
        try database.query(
            "SELECT id FROM tasks WHERE project_id = ? AND parent_id IS ? ORDER BY sort_order, id",
            .integer(projectID), .optional(parentID)
        ) { $0.int(0) }
    }

    private func openSiblings(projectID: Int64, parentID: Int64?) throws -> [Int64] {
        try database.query(
            "SELECT id FROM tasks WHERE project_id = ? AND parent_id IS ? AND is_completed = 0 ORDER BY sort_order, id",
            .integer(projectID), .optional(parentID)
        ) { $0.int(0) }
    }

    private func renumber(_ ids: [Int64]) throws {
        for (order, taskID) in ids.enumerated() {
            try database.run("UPDATE tasks SET sort_order = ? WHERE id = ?", .integer(Int64(order)), .integer(taskID))
        }
    }

    private func projectID(ofTask id: Int64) throws -> Int64? {
        try database.query("SELECT project_id FROM tasks WHERE id = ?", .integer(id)) { $0.int(0) }.first
    }

    private func parentID(ofTask id: Int64) throws -> Int64? {
        try database.query("SELECT parent_id FROM tasks WHERE id = ?", .integer(id)) { $0.optionalInt(0) }.first ?? nil
    }

    /// The task and all of its descendants.
    private func subtreeIDs(of id: Int64) throws -> [Int64] {
        try database.query(
            """
            WITH RECURSIVE subtree(id) AS (
                SELECT ? UNION ALL SELECT tasks.id FROM tasks JOIN subtree ON tasks.parent_id = subtree.id
            )
            SELECT id FROM subtree
            """,
            .integer(id)
        ) { $0.int(0) }
    }
}
