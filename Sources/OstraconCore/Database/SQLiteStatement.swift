import Foundation
import SQLite3

/// SQLite's destructor sentinel telling it to copy bound text immediately.
private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteStatement {
    let pointer: OpaquePointer
    private unowned let database: SQLiteDatabase

    init(pointer: OpaquePointer, database: SQLiteDatabase) {
        self.pointer = pointer
        self.database = database
    }

    deinit {
        sqlite3_finalize(pointer)
    }

    func bind(_ parameters: [SQLiteValue]) throws {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result = switch value {
            case .null: sqlite3_bind_null(pointer, index)
            case .integer(let number): sqlite3_bind_int64(pointer, index, number)
            case .real(let number): sqlite3_bind_double(pointer, index, number)
            case .text(let string): sqlite3_bind_text(pointer, index, string, -1, transientDestructor)
            }
            guard result == SQLITE_OK else {
                throw SQLiteError(code: result, message: database.lastErrorMessage)
            }
        }
    }

    /// Advances to the next row, returning `false` once the statement has finished.
    func step() throws -> Bool {
        let result = sqlite3_step(pointer)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError(code: result, message: database.lastErrorMessage)
        }
    }
}
