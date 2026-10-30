import Foundation
import SQLite3

/// A minimal wrapper over the SQLite C API.
///
/// Not thread-safe: confine each instance to a single actor.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens (creating if needed) the database at `path`. Pass `":memory:"` for an in-memory database.
    ///
    /// With `readOnly`, the file must already exist and is left exactly as it is.
    public init(path: String, readOnly: Bool = false) throws {
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let flags = access | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw SQLiteError(code: result, message: message)
        }
        // The app and the MCP server share the file, so wait out each other's writes rather than failing.
        sqlite3_busy_timeout(handle, 5_000)
        guard !readOnly else { return }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs one or more SQL statements that take no parameters and return no rows.
    public func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorPointer)
            throw SQLiteError(code: result, message: message)
        }
    }

    /// Runs a single statement with bound parameters, discarding any rows.
    public func run(_ sql: String, _ parameters: SQLiteValue...) throws {
        let statement = try prepare(sql, parameters)
        while try statement.step() {}
    }

    /// Runs a query and maps each row with `transform`.
    public func query<T>(_ sql: String, _ parameters: SQLiteValue..., transform: (SQLiteRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql, parameters)
        var results: [T] = []
        while try statement.step() {
            results.append(try transform(SQLiteRow(statement: statement)))
        }
        return results
    }

    /// Runs `body` inside a transaction, rolling back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Writes a consistent copy of the whole database to a new file at `path`: one file, with no journal beside it.
    public func copy(to path: String) throws {
        try run("VACUUM INTO ?", .text(path))
    }

    /// Replaces everything in this database with the contents of `source`, in one step that other connections
    /// to this database see as an ordinary write.
    public func replaceContents(with source: SQLiteDatabase) throws {
        guard let backup = sqlite3_backup_init(handle, "main", source.handle, "main") else {
            throw SQLiteError(code: sqlite3_errcode(handle), message: lastErrorMessage)
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else {
            throw SQLiteError(code: result, message: lastErrorMessage)
        }
    }

    public var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func prepare(_ sql: String, _ parameters: [SQLiteValue]) throws -> SQLiteStatement {
        var pointer: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &pointer, nil)
        guard result == SQLITE_OK, let pointer else {
            throw SQLiteError(code: result, message: lastErrorMessage)
        }
        let statement = SQLiteStatement(pointer: pointer, database: self)
        try statement.bind(parameters)
        return statement
    }
}
