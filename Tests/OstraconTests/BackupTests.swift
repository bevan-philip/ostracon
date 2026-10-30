import Foundation
@testable import Ostracon
import OstraconCore
import Testing

@MainActor
struct BackupTests {
    let directory: URL
    let backups: URL
    let settings: UserDefaults
    let model: AppModel
    let inboxID: Int64

    init() throws {
        directory = URL.temporaryDirectory.appending(path: "ostracon-app-backups-\(UUID().uuidString)", directoryHint: .isDirectory)
        backups = directory.appending(path: "OneDrive", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        settings = try #require(UserDefaults(suiteName: "ostracon-tests-\(UUID().uuidString)"))
        model = AppModel(repository: try .open(directory.appending(path: "ostracon.sqlite")), settings: settings)
        inboxID = try #require(model.selectedProjectID)
    }

    private func add(_ text: String) {
        model.submitComposer(mode: .add(parentID: nil), text: text, details: "", projectID: inboxID)
    }

    private func backedUpTasks() throws -> [String] {
        let backup = try #require(model.backupFolder?.backups().first)
        return try TaskRepository(database: SQLiteDatabase(path: backup.url.path(percentEncoded: false), readOnly: true))
            .tasks().map(\.content)
    }

    @Test func choosingAFolderBacksUpAtOnceAndIsRemembered() throws {
        add("First")
        model.setBackupFolder(backups)
        #expect(try backedUpTasks() == ["First"])
        #expect(model.lastBackupDate != nil)

        let reopened = AppModel(repository: try .inMemory(), settings: settings)
        #expect(reopened.backupFolder?.url.standardizedFileURL == backups.standardizedFileURL)
        #expect(reopened.lastBackupDate != nil)

        model.setBackupFolder(nil)
        #expect(AppModel(repository: try .inMemory(), settings: settings).backupFolder == nil)
    }

    @Test func backsUpChangesAtMostOncePerInterval() throws {
        let start = Date.now
        model.setBackupFolder(backups)
        add("Changed")

        model.backUpIfChanged(now: start.addingTimeInterval(10))
        #expect(try backedUpTasks() == [], "Too soon after the last backup")

        model.backUpIfChanged(now: start.addingTimeInterval(AppModel.backupInterval + 1))
        #expect(try backedUpTasks() == ["Changed"])
        let date = model.lastBackupDate

        model.backUpIfChanged(now: start.addingTimeInterval(AppModel.backupInterval * 3))
        #expect(model.lastBackupDate == date, "Nothing changed, so no backup")
    }

    @Test func quittingBacksUpWithoutWaiting() throws {
        model.setBackupFolder(backups)
        add("Last thing before quitting")
        model.backUpIfChanged(throttled: false)
        #expect(try backedUpTasks() == ["Last thing before quitting"])
    }

    @Test func picksUpChangesFromTheCommandLine() throws {
        model.setBackupFolder(backups)
        let cli = try TaskRepository.open(try #require(model.databaseURL))
        try cli.addTask(content: "From ostracon-cli", projectID: inboxID)
        model.backUpIfChanged(now: .now.addingTimeInterval(AppModel.backupInterval + 1))
        #expect(try backedUpTasks() == ["From ostracon-cli"])
    }

    @Test func reportsAFolderThatHasGoneAndRecovers() throws {
        model.setBackupFolder(backups)
        try FileManager.default.removeItem(at: backups)
        add("Changed")
        model.backUpNow()
        #expect(model.backupError != nil)

        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        model.backUpNow()
        #expect(model.backupError == nil)
        #expect(try backedUpTasks() == ["Changed"])
    }

    @Test func restoreKeepsTheReplacedTasks() throws {
        add("Backed up")
        model.setBackupFolder(backups)
        let backup = try #require(model.backupFolder?.backups().first)
        add("Not backed up")
        model.selectedTaskID = model.rows.last?.id

        model.restore(from: backup.url)
        #expect(model.rows.map(\.task.content) == ["Backed up"])
        #expect(model.selectedTaskID == nil)
        #expect(model.errorMessage == nil)

        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false))
        let saved = try #require(files.first { $0.hasPrefix("Ostracon before restore") })
        let previous = try TaskRepository(database: SQLiteDatabase(path: backups.appending(path: saved).path(percentEncoded: false), readOnly: true))
        #expect(try previous.tasks().map(\.content) == ["Backed up", "Not backed up"])
    }
}
