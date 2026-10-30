import Foundation
import OstraconCore
import Testing

struct BackupFolderTests {
    let directory: URL
    let folder: BackupFolder
    let repository: TaskRepository

    init() throws {
        directory = URL.temporaryDirectory.appending(path: "ostracon-backups-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory.appending(path: "Backups"), withIntermediateDirectories: true)
        folder = BackupFolder(url: directory.appending(path: "Backups"), retainedCount: 3)
        repository = try TaskRepository.open(directory.appending(path: "ostracon.sqlite"))
    }

    private func day(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func backupNames() -> [String] {
        folder.backups().map(\.url.lastPathComponent)
    }

    @Test func writesOneCompleteFilePerDay() throws {
        try repository.addTask(content: "Morning", projectID: repository.inbox().id)
        try folder.backUp(repository, now: day(30))
        try repository.addTask(content: "Afternoon", projectID: repository.inbox().id)
        let backup = try folder.backUp(repository, now: day(30))

        #expect(backupNames() == ["Ostracon 2026-10-30.sqlite"])
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false))
        #expect(files == ["Ostracon 2026-10-30.sqlite"], "No journal or log files beside it")
        let copy = try TaskRepository(database: SQLiteDatabase(path: backup.url.path(percentEncoded: false), readOnly: true))
        #expect(try copy.tasks().map(\.content) == ["Morning", "Afternoon"])
    }

    @Test func keepsOnlyTheNewestDays() throws {
        for date in [26, 27, 28, 29, 30] {
            try folder.backUp(repository, now: day(date))
        }
        try folder.backUp(repository, before: "restore", now: day(25))
        #expect(backupNames() == ["Ostracon 2026-10-30.sqlite", "Ostracon 2026-10-29.sqlite", "Ostracon 2026-10-28.sqlite"])
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false))
        #expect(files.contains("Ostracon before restore 2026-10-25 12.00.00.sqlite"), "One-off backups are never pruned")
    }

    @Test func failsWhenTheFolderIsGone() throws {
        let missing = BackupFolder(url: directory.appending(path: "Not There"))
        #expect(throws: CocoaError.self) { try missing.backUp(self.repository) }
        #expect(!FileManager.default.fileExists(atPath: missing.url.path(percentEncoded: false)))
    }

    @Test func restoreReplacesEverythingAndOtherConnectionsNotice() throws {
        let inbox = try repository.inbox()
        try repository.createProject(name: "Work", color: .grape)
        try repository.addTask(content: "Backed up", projectID: inbox.id, reminders: [.before(minutes: 5)])
        let backup = try folder.backUp(repository, now: day(30))

        try repository.addTask(content: "Added later", projectID: inbox.id)
        try repository.deleteProject(id: try #require(repository.projects().last).id)
        let other = try TaskRepository.open(try #require(repository.url))
        _ = try other.hasExternalChanges()

        try repository.restore(from: backup.url)
        #expect(try repository.projects().map(\.name) == ["Inbox", "Work"])
        #expect(try repository.tasks().map(\.content) == ["Backed up"])
        #expect(try repository.tasks().first?.reminders == [.before(minutes: 5)])
        #expect(try other.hasExternalChanges(), "The CLI or app sees the restore as a change")
        #expect(try other.tasks().map(\.content) == ["Backed up"])
    }

    @Test func restoreRefusesFilesThatArentOstraconDatabases() throws {
        let text = directory.appending(path: "notes.sqlite")
        try Data("not a database".utf8).write(to: text)
        let other = directory.appending(path: "other.sqlite")
        try SQLiteDatabase(path: other.path(percentEncoded: false)).execute("CREATE TABLE things (id INTEGER)")
        try repository.addTask(content: "Kept", projectID: repository.inbox().id)

        for file in [text, other] {
            #expect(throws: RepositoryError.self) { try self.repository.restore(from: file) }
        }
        #expect(try repository.tasks().map(\.content) == ["Kept"])
    }
}
