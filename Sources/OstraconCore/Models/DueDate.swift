import Foundation

/// When a task is due: a calendar day, optionally at a time of day.
///
/// Stored as floating local time, as in Todoist, so "Friday at 9:00" stays 9:00 if the time zone changes.
public struct DueDate: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var time: TimeOfDay?

    public init(year: Int, month: Int, day: Int, time: TimeOfDay? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.time = time
    }

    /// The day containing `date`, at `time` if given.
    public init(day date: Date, time: TimeOfDay? = nil, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1, time: time)
    }

    /// The day and time of `date`, to the minute.
    public init(dayAndTime date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(day: date, time: TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0), calendar: calendar)
    }

    public var hasTime: Bool { time != nil }

    /// The due moment, or the start of the day when there is no time.
    public func date(in calendar: Calendar = .current) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: time?.hour ?? 0, minute: time?.minute ?? 0)
        return calendar.date(from: parts) ?? .distantPast
    }

    /// The start of the due day.
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func withTime(_ time: TimeOfDay?) -> DueDate {
        DueDate(year: year, month: month, day: day, time: time)
    }

    /// Whole days from the start of `now`'s day to the due day: 0 for today, negative when past.
    public func daysFrom(_ now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: startOfDay(in: calendar)).day ?? 0
    }

    /// Overdue once the due time has passed, or for all-day tasks once the day is over.
    public func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        hasTime ? date(in: calendar) < now : daysFrom(now, calendar: calendar) < 0
    }

    // MARK: - Storage

    /// `yyyy-MM-dd`, or `yyyy-MM-ddTHH:mm` with a time.
    public var storageValue: String {
        let day = String(format: "%04d-%02d-%02d", year, month, self.day)
        guard let time else { return day }
        return day + String(format: "T%02d:%02d", time.hour, time.minute)
    }

    public init?(storageValue: String) {
        let halves = storageValue.split(separator: "T")
        let dayParts = halves.first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard dayParts.count == 3 else { return nil }
        var time: TimeOfDay?
        if halves.count == 2 {
            let timeParts = halves[1].split(separator: ":").compactMap { Int($0) }
            guard timeParts.count == 2 else { return nil }
            time = TimeOfDay(hour: timeParts[0], minute: timeParts[1])
        }
        self.init(year: dayParts[0], month: dayParts[1], day: dayParts[2], time: time)
    }
}

public struct TimeOfDay: Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    /// Where untimed reminders land.
    public static let morning = TimeOfDay(hour: 9)

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}
