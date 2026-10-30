import Foundation

/// A value that can be bound to a statement parameter.
public enum SQLiteValue: Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    public static func optional(_ value: Int64?) -> SQLiteValue {
        value.map(SQLiteValue.integer) ?? .null
    }

    public static func optional(_ value: Double?) -> SQLiteValue {
        value.map(SQLiteValue.real) ?? .null
    }

    public static func optional(_ value: String?) -> SQLiteValue {
        value.map(SQLiteValue.text) ?? .null
    }

    public static func bool(_ value: Bool) -> SQLiteValue {
        .integer(value ? 1 : 0)
    }
}
