import Foundation
import SQLite3

/// Read access to the current row of a query, by zero-based column index.
public struct SQLiteRow {
    let statement: SQLiteStatement

    public func int(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement.pointer, column)
    }

    public func optionalInt(_ column: Int32) -> Int64? {
        sqlite3_column_type(statement.pointer, column) == SQLITE_NULL ? nil : int(column)
    }

    public func double(_ column: Int32) -> Double {
        sqlite3_column_double(statement.pointer, column)
    }

    public func optionalDouble(_ column: Int32) -> Double? {
        sqlite3_column_type(statement.pointer, column) == SQLITE_NULL ? nil : double(column)
    }

    public func bool(_ column: Int32) -> Bool {
        int(column) != 0
    }

    public func text(_ column: Int32) -> String {
        guard let cString = sqlite3_column_text(statement.pointer, column) else { return "" }
        return String(cString: cString)
    }
}
