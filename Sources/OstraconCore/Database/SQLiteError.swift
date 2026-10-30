import Foundation

public struct SQLiteError: Error, LocalizedError, Equatable {
    public let code: Int32
    public let message: String

    public var errorDescription: String? {
        "SQLite error \(code): \(message)"
    }
}
