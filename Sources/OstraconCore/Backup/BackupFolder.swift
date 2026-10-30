import Foundation

/// A folder of daily copies of the database, typically one that OneDrive, iCloud Drive or Dropbox syncs.
///
/// The database itself stays on this Mac, where the app, `ostracon-mcp` and `ostracon-cli` can share it safely.
/// Sync services upload each file whenever they notice it change, so a live SQLite database there could be
/// uploaded halfway through a write. Backups are instead written in full elsewhere and moved into the folder,
/// so all a sync service ever sees is a complete file.
public struct BackupFolder: Sendable {
    public struct Backup: Equatable, Sendable {
        public var url: URL
        /// When the backup was written.
        public var date: Date
    }

    public var url: URL
    /// How many daily backups to keep; older ones are deleted after each backup.
    public var retainedCount: Int

    public init(url: URL, retainedCount: Int = 2) {
        self.url = url
        self.retainedCount = retainedCount
    }

    /// The daily backups, newest first.
    public func backups() -> [Backup] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
        return files
            .filter { $0.lastPathComponent.wholeMatch(of: /Ostracon \d{4}-\d{2}-\d{2}\.sqlite/) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { file in
                let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return Backup(url: file, date: date ?? .distantPast)
            }
    }

    /// Writes today's backup, replacing one from earlier today, then deletes all but the newest `retainedCount`.
    @discardableResult
    public func backUp(_ repository: TaskRepository, now: Date = .now) throws -> Backup {
        let backup = try write(repository, named: "Ostracon \(now.formatted(Self.day)).sqlite")
        for old in backups().dropFirst(retainedCount) {
            try? FileManager.default.removeItem(at: old.url)
        }
        return backup
    }

    /// Writes a one-off backup that is never deleted, e.g. of tasks about to be replaced by a restore.
    @discardableResult
    public func backUp(_ repository: TaskRepository, before reason: String, now: Date = .now) throws -> Backup {
        try write(repository, named: "Ostracon before \(reason) \(now.formatted(Self.day)) \(now.formatted(Self.time)).sqlite")
    }

    private func write(_ repository: TaskRepository, named name: String) throws -> Backup {
        let fileManager = FileManager.default
        guard (try? url.checkResourceIsReachable()) == true else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
        }
        let destination = url.appending(path: name)
        // Write on the same volume, outside the synced folder, then move the finished file in.
        let scratch = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let written = scratch.appending(path: name)
        try repository.copy(to: written)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: written)
        } else {
            try fileManager.moveItem(at: written, to: destination)
        }
        return Backup(url: destination, date: .now)
    }

    private static let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    private static let time = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
        timeZone: .current, calendar: .current
    )
}
