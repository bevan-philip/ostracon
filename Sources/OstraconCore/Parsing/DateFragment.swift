import Foundation

/// A day and/or time as written, before defaults are filled in. `DateParser.resolve` turns it into a `DueDate`.
public struct DateFragment: Hashable, Sendable {
    /// The start of the day, if one was given.
    public var day: Date?
    public var time: TimeOfDay?

    public init(day: Date? = nil, time: TimeOfDay? = nil) {
        self.day = day
        self.time = time
    }

    /// One gives only a day and the other only a time, so together they make a whole date ("5pm … tomorrow").
    public func complements(_ other: DateFragment) -> Bool {
        (isDayOnly && other.isTimeOnly) || (isTimeOnly && other.isDayOnly)
    }

    private var isDayOnly: Bool { day != nil && time == nil }
    private var isTimeOnly: Bool { day == nil && time != nil }

    public func combined(with other: DateFragment) -> DateFragment {
        DateFragment(day: day ?? other.day, time: time ?? other.time)
    }
}

/// A reminder as written, before it's tied to a due date.
public enum ReminderFragment: Hashable, Sendable {
    case before(minutes: Int)
    case at(DateFragment)
}
